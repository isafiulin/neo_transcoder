package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"

	"neotranscoder/internal/buildinfo"
	"neotranscoder/internal/config"
	"neotranscoder/internal/doctor"
	"neotranscoder/internal/installer"
	"neotranscoder/internal/server"
)

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(args []string) int {
	if len(args) == 0 {
		args = []string{"serve"}
	}

	switch args[0] {
	case "serve":
		return serve(args[1:])
	case "version":
		fmt.Printf("neotranscoder %s commit=%s date=%s\n", buildinfo.Version, buildinfo.Commit, buildinfo.Date)
		return 0
	case "doctor":
		return runDoctor(args[1:])
	case "init":
		return runInit(args[1:])
	case "config":
		return runConfig(args[1:])
	case "uninstall":
		return runScript("/usr/local/lib/neotranscoder/uninstall.sh", args[1:])
	case "update":
		return runScript("/usr/local/lib/neotranscoder/update.sh", args[1:])
	default:
		fmt.Fprintf(os.Stderr, "unknown command %q\n", args[0])
		usage()
		return 2
	}
}

func runInit(args []string) int {
	fs := flag.NewFlagSet("init", flag.ContinueOnError)
	port := fs.Int("port", 0, "web management port")
	yes := fs.Bool("yes", false, "use defaults without prompts")
	forceConfig := fs.Bool("force-config", false, "rewrite default config before applying options")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if err := installer.Run(installer.Options{
		Port:        *port,
		Yes:         *yes,
		ForceConfig: *forceConfig,
	}); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	return 0
}

func serve(args []string) int {
	fs := flag.NewFlagSet("serve", flag.ContinueOnError)
	configPath := fs.String("config", config.DefaultPath, "config file path")
	if err := fs.Parse(args); err != nil {
		return 2
	}

	cfg, err := config.Load(*configPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	log, closeLog := newLogger(cfg)
	defer closeLog()
	srv, err := server.New(cfg, log)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	if err := srv.Run(ctx); err != nil {
		log.Error("server stopped", "error", err)
		return 1
	}
	return 0
}

// newLogger wires cfg.Logs.Path/Level into the daemon logger. Before this,
// the logger was hardcoded to os.Stdout only, so logs.path in config.json was
// validated and checked for a writable directory (doctor.go) but nothing
// ever wrote to it — the file stayed empty forever, and journald (via
// systemd capturing stdout) was the only real log target.
func newLogger(cfg config.Config) (*slog.Logger, func()) {
	writer := io.Writer(os.Stdout)
	closer := func() {}

	if cfg.Logs.Path != "" {
		if err := os.MkdirAll(filepath.Dir(cfg.Logs.Path), 0o755); err != nil {
			fmt.Fprintf(os.Stderr, "warning: cannot create log directory for %s: %v\n", cfg.Logs.Path, err)
		} else if file, err := os.OpenFile(cfg.Logs.Path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644); err != nil {
			fmt.Fprintf(os.Stderr, "warning: cannot open log file %s: %v\n", cfg.Logs.Path, err)
		} else {
			// ponytail: keep stdout too, so `journalctl -u neotranscoder` still
			// works under systemd; the file is the durable copy.
			writer = io.MultiWriter(os.Stdout, file)
			closer = func() { _ = file.Close() }
		}
	}

	handler := slog.NewTextHandler(writer, &slog.HandlerOptions{Level: parseLevel(cfg.Logs.Level)})
	return slog.New(handler), closer
}

func parseLevel(level string) slog.Level {
	switch strings.ToLower(level) {
	case "debug":
		return slog.LevelDebug
	case "warn", "warning":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}

func runDoctor(args []string) int {
	fs := flag.NewFlagSet("doctor", flag.ContinueOnError)
	configPath := fs.String("config", config.DefaultPath, "config file path")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	cfg, err := config.Load(*configPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	checks := doctor.Run(cfg)
	failed := false
	for _, check := range checks {
		status := "ok"
		if !check.OK {
			status = "fail"
			failed = true
		}
		fmt.Printf("%-12s %-4s %s\n", check.Name, status, check.Detail)
	}
	if failed {
		return 1
	}
	return 0
}

func runConfig(args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "usage: neotranscoder config validate|write-default|set-server")
		return 2
	}

	fs := flag.NewFlagSet("config "+args[0], flag.ContinueOnError)
	configPath := fs.String("config", config.DefaultPath, "config file path")
	bind := fs.String("bind", "", "server bind IP")
	port := fs.Int("port", 0, "server port")
	if err := fs.Parse(args[1:]); err != nil {
		return 2
	}

	switch args[0] {
	case "validate":
		if _, err := config.Load(*configPath); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		fmt.Println("config ok")
		return 0
	case "write-default":
		if err := config.WriteDefault(*configPath); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		fmt.Println(*configPath)
		return 0
	case "set-server":
		cfg, err := config.Load(*configPath)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		if *bind != "" {
			cfg.Server.Bind = *bind
		}
		if *port != 0 {
			cfg.Server.Port = *port
		}
		if err := config.Write(*configPath, cfg); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		fmt.Println(*configPath)
		return 0
	default:
		fmt.Fprintf(os.Stderr, "unknown config command %q\n", args[0])
		return 2
	}
}

func runScript(path string, args []string) int {
	cmdArgs := append([]string{path}, args...)
	if err := syscall.Exec(path, cmdArgs, os.Environ()); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	return 0
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: neotranscoder [serve|version|doctor|init|config|update|uninstall]")
}

package installer

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"neotranscoder/internal/config"
	"neotranscoder/internal/doctor"
)

const (
	ServiceName = "neotranscoder"
	BinPath     = "/usr/local/bin/neotranscoder"
	LibDir      = "/usr/local/lib/neotranscoder"
	ConfigDir   = "/etc/neotranscoder"
	StateDir    = "/var/lib/neotranscoder"
	LogDir      = "/var/log/neotranscoder"
	UnitPath    = "/etc/systemd/system/neotranscoder.service"
)

type Options struct {
	Port        int
	ForceConfig bool
	Yes         bool
	SourcePath  string
	Stdin       io.Reader
	Stdout      io.Writer
	Stderr      io.Writer
}

func Run(opts Options) error {
	stdout := writer(opts.Stdout, os.Stdout)
	stderr := writer(opts.Stderr, os.Stderr)
	if os.Geteuid() != 0 {
		return errors.New("run as root")
	}
	source := opts.SourcePath
	if source == "" {
		exe, err := os.Executable()
		if err != nil {
			return err
		}
		source = exe
	}
	if opts.Port == 0 && !opts.Yes {
		port, err := promptPort(opts.Stdin, stdout, config.Default().Server.Port)
		if err != nil {
			return err
		}
		opts.Port = port
	}
	if opts.Port == 0 {
		opts.Port = config.Default().Server.Port
	}
	if err := validatePort(opts.Port); err != nil {
		return err
	}

	fmt.Fprintln(stdout, "NeoTranscoder init")
	fmt.Fprintf(stdout, "web: 0.0.0.0:%d\n", opts.Port)

	if err := ensureUser(); err != nil {
		return err
	}
	for _, dir := range []string{ConfigDir, StateDir, LogDir, LibDir, backupDir()} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
	}
	if err := installBinary(source, BinPath); err != nil {
		return err
	}
	if err := installHelperScripts(filepath.Dir(source)); err != nil {
		return err
	}
	if err := writeConfig(opts.Port, opts.ForceConfig); err != nil {
		return err
	}
	if err := writeUnit(); err != nil {
		return err
	}
	_ = exec.Command("chown", "-R", ServiceName+":"+ServiceName, StateDir, LogDir).Run()

	cfg, err := config.Load(filepath.Join(ConfigDir, "config.json"))
	if err != nil {
		return err
	}
	failed := printDoctor(stdout, doctor.Run(cfg))
	if failed {
		fmt.Fprintf(stderr, "doctor reported missing requirements; install ffmpeg/ffprobe before production streams\n")
	}

	if err := run("systemctl", "daemon-reload"); err != nil {
		return err
	}
	if err := run("systemctl", "enable", "--now", ServiceName); err != nil {
		return err
	}
	fmt.Fprintf(stdout, "installed: systemctl status %s\n", ServiceName)
	return nil
}

func promptPort(stdin io.Reader, stdout io.Writer, fallback int) (int, error) {
	if stdin == nil {
		stdin = os.Stdin
	}
	reader := bufio.NewReader(stdin)
	for {
		fmt.Fprintf(stdout, "Web port [%d]: ", fallback)
		line, err := reader.ReadString('\n')
		if err != nil && !errors.Is(err, io.EOF) {
			return 0, err
		}
		line = strings.TrimSpace(line)
		if line == "" {
			return fallback, nil
		}
		port, parseErr := strconv.Atoi(line)
		if parseErr == nil {
			if err := validatePort(port); err == nil {
				return port, nil
			}
		}
		fmt.Fprintln(stdout, "Port must be between 1 and 65535.")
		if errors.Is(err, io.EOF) {
			return 0, errors.New("invalid port")
		}
	}
}

func validatePort(port int) error {
	if port < 1 || port > 65535 {
		return fmt.Errorf("port must be between 1 and 65535")
	}
	return nil
}

func ensureUser() error {
	if exec.Command("id", ServiceName).Run() == nil {
		return nil
	}
	return run("useradd", "--system", "--home", StateDir, "--shell", "/usr/sbin/nologin", ServiceName)
}

func installBinary(source, target string) error {
	sourcePath, err := filepath.Abs(source)
	if err != nil {
		return err
	}
	targetPath, err := filepath.Abs(target)
	if err != nil {
		return err
	}
	if sourcePath == targetPath {
		return nil
	}
	if _, err := os.Stat(target); err == nil {
		backup := filepath.Join(backupDir(), "neotranscoder."+time.Now().UTC().Format("20060102T150405Z"))
		if err := copyFile(target, backup, 0o755); err != nil {
			return err
		}
	}
	return copyFile(source, target, 0o755)
}

func installHelperScripts(sourceDir string) error {
	for _, name := range []string{"install.sh", "update.sh", "uninstall.sh"} {
		source := filepath.Join(sourceDir, name)
		if _, err := os.Stat(source); err != nil {
			continue
		}
		if err := copyFile(source, filepath.Join(LibDir, name), 0o755); err != nil {
			return err
		}
	}
	return nil
}

func writeConfig(port int, force bool) error {
	path := filepath.Join(ConfigDir, "config.json")
	cfg := config.Default()
	if !force {
		if existing, err := config.Load(path); err == nil {
			cfg = existing
		}
	}
	cfg.Server.Bind = net.IPv4zero.String()
	cfg.Server.Port = port
	return config.Write(path, cfg)
}

func writeUnit() error {
	unit := `[Unit]
Description=NeoTranscoder multicast transcoder manager
After=network-online.target
Wants=network-online.target

[Service]
User=neotranscoder
Group=neotranscoder
ExecStart=/usr/local/bin/neotranscoder serve --config /etc/neotranscoder/config.json
Restart=always
RestartSec=5
LimitNOFILE=1048576
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
`
	return os.WriteFile(UnitPath, []byte(unit), 0o644)
}

func printDoctor(stdout io.Writer, checks []doctor.Check) bool {
	failed := false
	for _, check := range checks {
		status := "ok"
		if !check.OK {
			status = "fail"
			failed = true
		}
		fmt.Fprintf(stdout, "%-12s %-4s %s\n", check.Name, status, check.Detail)
	}
	return failed
}

func copyFile(source, target string, mode os.FileMode) error {
	input, err := os.Open(source)
	if err != nil {
		return err
	}
	defer input.Close()
	tmp := target + ".tmp"
	output, err := os.OpenFile(tmp, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, mode)
	if err != nil {
		return err
	}
	if _, err := io.Copy(output, input); err != nil {
		_ = output.Close()
		return err
	}
	if err := output.Close(); err != nil {
		return err
	}
	return os.Rename(tmp, target)
}

func backupDir() string {
	return filepath.Join(StateDir, "backups")
}

func run(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("%s %s: %w: %s", name, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return nil
}

func writer(value io.Writer, fallback io.Writer) io.Writer {
	if value != nil {
		return value
	}
	return fallback
}

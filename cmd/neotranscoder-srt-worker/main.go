package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/signal"
	"runtime"
	"syscall"

	"neotranscoder/internal/buildinfo"
	"neotranscoder/internal/srtrelay"
	"neotranscoder/internal/srtworker"
)

func main() {
	if len(os.Args) == 2 && os.Args[1] == "version" {
		fmt.Printf("neotranscoder-srt-worker %s commit=%s date=%s\n", buildinfo.Version, buildinfo.Commit, buildinfo.Date)
		return
	}
	if len(os.Args) != 2 || os.Args[1] != "--config-stdin" {
		fmt.Fprintln(os.Stderr, "usage: neotranscoder-srt-worker [version|--config-stdin]")
		os.Exit(2)
	}
	var config srtrelay.WorkerConfig
	decoder := json.NewDecoder(os.Stdin)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&config); err != nil {
		fmt.Fprintln(os.Stderr, "read worker config:", err)
		os.Exit(2)
	}
	if os.Getenv("GOMAXPROCS") == "" {
		// The input loop sleeps inside C while holding a P. A second P lets
		// sysmon leave that call alone instead of retaking it every 20 us;
		// more Ps only add idle threads across dozens of workers.
		runtime.GOMAXPROCS(2)
	}
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	if err := srtworker.Run(ctx, config, os.Stdout, os.Stderr); err != nil {
		os.Exit(1)
	}
}

package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/signal"
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
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	if err := srtworker.Run(ctx, config, os.Stdout, os.Stderr); err != nil {
		os.Exit(1)
	}
}

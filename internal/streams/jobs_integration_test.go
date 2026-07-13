package streams

import (
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"testing"
	"time"

	"neotranscoder/internal/ffmpeg"
)

func TestJobManagerCapturesProgressLogsAndStopsProcess(t *testing.T) {
	store := testJobStore(t, "channel-1")
	worker := writeFakeFFmpeg(t, `
printf 'frame=25\nfps=25.0\nbitrate=1000kbits/s\nprogress=continue\n'
printf '[warning] input packet warning\n' >&2
trap 'exit 0' TERM INT
while :; do sleep 1; done
`)
	manager := NewJobManager(worker, ffmpeg.SystemConfig{}, store, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err := manager.Start("channel-1"); err != nil {
		t.Fatal(err)
	}
	waitStreamState(t, store, "channel-1", func(state State) bool {
		return state.Status == "running" && state.Metrics != nil && state.Metrics.Frame == 25
	}, 5*time.Second)
	if err := manager.Start("channel-1"); err == nil {
		t.Fatal("duplicate stream start was accepted")
	}
	if err := manager.Stop("channel-1"); err != nil {
		t.Fatal(err)
	}
	view, _ := store.Get("channel-1")
	if view.State.Status != "stopped" || view.State.PID != 0 {
		t.Fatalf("stopped stream state = %+v", view.State)
	}
	if logs := store.Logs("channel-1", 20); len(logs) == 0 {
		t.Fatal("stderr warning was not captured")
	}
}

func TestJobManagerRecordsUnexpectedProcessExitWithoutRestart(t *testing.T) {
	store := testJobStore(t, "channel-1")
	worker := writeFakeFFmpeg(t, "printf '[error] encoder failed\\n' >&2\nexit 7\n")
	manager := NewJobManager(worker, ffmpeg.SystemConfig{}, store, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err := manager.Start("channel-1"); err != nil {
		t.Fatal(err)
	}
	waitStreamState(t, store, "channel-1", func(state State) bool {
		return state.Status == "error" && state.PID == 0
	}, 5*time.Second)
	view, _ := store.Get("channel-1")
	if view.State.ErrorCode == "" || view.State.LastError == "" {
		t.Fatalf("failed stream state = %+v", view.State)
	}
	if err := manager.Stop("channel-1"); err == nil {
		t.Fatal("stopping an exited stream unexpectedly succeeded")
	}
}

func testJobStore(t *testing.T, id string) *Store {
	t.Helper()
	store, err := NewStore(filepath.Join(t.TempDir(), "state.json"))
	if err != nil {
		t.Fatal(err)
	}
	_, err = store.Upsert(Config{
		ID: id, InputURL: "udp://239.1.1.1:1234", OutputURL: "udp://239.2.2.2:1234",
		Enabled: false,
	})
	if err != nil {
		t.Fatal(err)
	}
	return store
}

func writeFakeFFmpeg(t *testing.T, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "fake-ffmpeg")
	if err := os.WriteFile(path, []byte("#!/bin/sh\nset -eu\n"+body), 0o755); err != nil {
		t.Fatal(err)
	}
	return path
}

func waitStreamState(t *testing.T, store *Store, id string, ready func(State) bool, timeout time.Duration) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		view, ok := store.Get(id)
		if ok && ready(view.State) {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	view, _ := store.Get(id)
	t.Fatalf("stream state did not converge: %+v", view.State)
}

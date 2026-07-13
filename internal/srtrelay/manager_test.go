package srtrelay

import (
	"fmt"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestManagerStartStopAndPassesSecretsOnlyThroughStdin(t *testing.T) {
	store := testStore(t)
	createManagerRelayAndClient(t, store)
	dir := t.TempDir()
	capture := filepath.Join(dir, "worker-config.json")
	worker := writeWorkerScript(t, dir, fmt.Sprintf(`
IFS= read -r config
printf '%%s' "$config" > %q
printf '{"type":"relay_ready"}\n'
trap 'exit 0' TERM INT
while :; do sleep 1; done
`, capture))
	manager := NewManager(worker, store, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err := manager.Start("news-srt"); err != nil {
		t.Fatal(err)
	}
	waitRelayStatus(t, store, "news-srt", "running", 5*time.Second)

	secret := store.WorkerClients("news-srt")[0].Passphrase
	manager.mu.Lock()
	args := strings.Join(manager.jobs["news-srt"].cmd.Args, " ")
	manager.mu.Unlock()
	if strings.Contains(args, secret) {
		t.Fatal("SRT passphrase leaked into worker arguments")
	}
	configData, err := os.ReadFile(capture)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(configData), secret) || !strings.Contains(string(configData), "news-srt") {
		t.Fatalf("worker stdin config missing expected values: %s", configData)
	}

	if err := manager.Stop("news-srt"); err != nil {
		t.Fatal(err)
	}
	waitRelayStatus(t, store, "news-srt", "stopped", 5*time.Second)
	if manager.IsRunning("news-srt") {
		t.Fatal("worker remained registered after stop")
	}
}

func TestManagerCrashMarksRelayFlappingAfterRestartLimit(t *testing.T) {
	store := testStore(t)
	createManagerRelayAndClient(t, store)
	worker := writeWorkerScript(t, t.TempDir(), `
IFS= read -r config
printf '{"type":"relay_ready"}\n'
sleep 1
exit 7
`)
	manager := NewManager(worker, store, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err := manager.Start("news-srt"); err != nil {
		t.Fatal(err)
	}
	manager.mu.Lock()
	manager.restarts["news-srt"] = restartTracker{
		firstFailure: time.Now(), attempts: maxRestarts,
	}
	manager.mu.Unlock()

	waitRelayStatus(t, store, "news-srt", "flapping", 6*time.Second)
	view, _ := store.GetRelay("news-srt")
	if !view.State.Flapping || view.State.PID != 0 || view.State.LastError == "" {
		t.Fatalf("flapping state = %+v", view.State)
	}
	events, err := store.Audit(AuditFilter{RelayID: "news-srt", Type: "relay_worker_exited", Limit: 10})
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 1 || events[0].Level != "error" {
		t.Fatalf("worker exit audit = %+v", events)
	}
}

func TestManagerRestartsWorkerAfterSingleCrash(t *testing.T) {
	store := testStore(t)
	createManagerRelayAndClient(t, store)
	dir := t.TempDir()
	marker := filepath.Join(dir, "already-crashed")
	worker := writeWorkerScript(t, dir, fmt.Sprintf(`
IFS= read -r config
if [ ! -f %q ]; then
  : > %q
  exit 3
fi
printf '{"type":"relay_ready"}\n'
trap 'exit 0' TERM INT
while :; do sleep 1; done
`, marker, marker))
	manager := NewManager(worker, store, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err := manager.Start("news-srt"); err != nil {
		t.Fatal(err)
	}
	waitRelayStatus(t, store, "news-srt", "running", restartBackoff+3*time.Second)
	view, _ := store.GetRelay("news-srt")
	if view.State.RestartCount != 1 || view.State.PID == 0 {
		t.Fatalf("restarted state = %+v", view.State)
	}
	if err := manager.Stop("news-srt"); err != nil {
		t.Fatal(err)
	}
	waitRelayStatus(t, store, "news-srt", "stopped", 5*time.Second)
}

func TestManagerRestartWindowIsBoundedAndResets(t *testing.T) {
	manager := NewManager("unused", testStore(t), slog.New(slog.NewTextHandler(io.Discard, nil)))
	now := time.Now()
	for attempt := 0; attempt < maxRestarts; attempt++ {
		if !manager.allowRestart("relay-a", now.Add(time.Duration(attempt)*time.Second)) {
			t.Fatalf("restart %d unexpectedly rejected", attempt+1)
		}
	}
	if manager.allowRestart("relay-a", now.Add(time.Minute)) {
		t.Fatal("restart above the window limit was accepted")
	}
	if !manager.allowRestart("relay-a", now.Add(restartWindow+time.Second)) {
		t.Fatal("restart window did not reset")
	}
}

func createManagerRelayAndClient(t *testing.T, store *Store) {
	t.Helper()
	_, err := store.UpsertRelay(Relay{
		ID: "news-srt", InputURL: "udp://239.10.10.1:1234",
		BindAddress: "0.0.0.0", Port: 9000, Enabled: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	_, err = store.UpsertClient(Client{
		ID: "partner-a", Enabled: true, AllowedRelayIDs: []string{"news-srt"},
		AllowedCIDRs: []string{"203.0.113.10"}, MaxSessions: 1,
	})
	if err != nil {
		t.Fatal(err)
	}
}

func writeWorkerScript(t *testing.T, dir, body string) string {
	t.Helper()
	path := filepath.Join(dir, "fake-srt-worker")
	if err := os.WriteFile(path, []byte("#!/bin/sh\nset -eu\n"+body), 0o755); err != nil {
		t.Fatal(err)
	}
	return path
}

func waitRelayStatus(t *testing.T, store *Store, id, expected string, timeout time.Duration) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		view, ok := store.GetRelay(id)
		if ok && view.State.Status == expected {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	view, _ := store.GetRelay(id)
	t.Fatalf("relay status = %q, want %q", view.State.Status, expected)
}

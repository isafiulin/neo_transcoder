package srtworker

import (
	"testing"
	"time"

	"neotranscoder/internal/srtrelay"
)

func TestInputStallReason(t *testing.T) {
	now := time.Unix(100, 0)
	if reason := inputStallReason(now, now.Add(-9*time.Second), 10*time.Second); reason != "" {
		t.Fatalf("early stall reason = %q", reason)
	}
	if reason := inputStallReason(now, now.Add(-10*time.Second), 10*time.Second); reason == "" {
		t.Fatal("expected stall reason at timeout")
	}
}

func TestWorkerInputTimeoutDefaultAndValidation(t *testing.T) {
	worker, err := newWorker(srtrelay.WorkerConfig{})
	if err != nil {
		t.Fatal(err)
	}
	if worker.config.Relay.InputTimeoutSeconds != 10 {
		t.Fatalf("default timeout = %d", worker.config.Relay.InputTimeoutSeconds)
	}
	_, err = newWorker(srtrelay.WorkerConfig{
		Relay: srtrelay.Relay{InputTimeoutSeconds: 301},
	})
	if err == nil {
		t.Fatal("expected invalid input timeout error")
	}
}

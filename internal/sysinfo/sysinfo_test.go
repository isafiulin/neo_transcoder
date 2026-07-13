package sysinfo

import (
	"context"
	"testing"
	"time"
)

func TestCollectorSamplesAndStopsWithContext(t *testing.T) {
	collector := NewCollector(t.TempDir())
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		collector.Run(ctx)
		close(done)
	}()
	time.Sleep(20 * time.Millisecond)
	snapshot := collector.Snapshot()
	if snapshot.CPUCores < 1 || snapshot.AppUptimeSeconds < 0 {
		t.Fatalf("snapshot = %+v", snapshot)
	}
	cancel()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("collector did not stop after context cancellation")
	}
}

func TestCollectorDefaultsDiskPath(t *testing.T) {
	collector := NewCollector("")
	if collector.diskPath != "/" {
		t.Fatalf("disk path = %q", collector.diskPath)
	}
}

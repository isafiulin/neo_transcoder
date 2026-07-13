package srtworker

import (
	"fmt"
	"testing"
	"time"
)

func TestConnectionAttemptRateLimit(t *testing.T) {
	w := &worker{attempts: make(map[string]attemptWindow)}
	now := time.Date(2026, 7, 13, 10, 0, 0, 0, time.UTC)
	for attempt := 0; attempt < 60; attempt++ {
		allowed, _ := w.allowConnectionAttempt("203.0.113.5", now)
		if !allowed {
			t.Fatalf("attempt %d was rejected", attempt+1)
		}
	}
	allowed, report := w.allowConnectionAttempt("203.0.113.5", now)
	if allowed || !report {
		t.Fatal("first limited attempt must be rejected and reported")
	}
	allowed, report = w.allowConnectionAttempt("203.0.113.5", now)
	if allowed || report {
		t.Fatal("subsequent limited attempt must be rejected without log amplification")
	}
	allowed, _ = w.allowConnectionAttempt("203.0.113.5", now.Add(time.Minute))
	if !allowed {
		t.Fatal("new window did not reset the limit")
	}
}

func TestConnectionAttemptLimiterHasHardMemoryCeiling(t *testing.T) {
	w := &worker{attempts: make(map[string]attemptWindow)}
	now := time.Date(2026, 7, 13, 10, 0, 0, 0, time.UTC)
	for index := 0; index < 10000; index++ {
		allowed, _ := w.allowConnectionAttempt(fmt.Sprintf("198.51.%d.%d", index/256, index%256), now)
		if !allowed {
			t.Fatalf("unique IP %d unexpectedly rejected", index)
		}
	}
	allowed, report := w.allowConnectionAttempt("203.0.113.250", now)
	if allowed || report || len(w.attempts) != 10000 {
		t.Fatalf("memory ceiling: allowed=%v report=%v tracked=%d", allowed, report, len(w.attempts))
	}
	allowed, _ = w.allowConnectionAttempt("203.0.113.250", now.Add(time.Minute))
	if !allowed {
		t.Fatal("stale limiter entries were not pruned")
	}
}

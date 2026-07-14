package srtrelay

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

func TestAuditListReturnsNewestMatchesWithBoundedLimit(t *testing.T) {
	store, err := NewAuditStore(t.TempDir(), 30)
	if err != nil {
		t.Fatal(err)
	}
	for index := 0; index < 5; index++ {
		_, err := store.Append(AuditEvent{
			Type: "connection_rejected", RelayID: "relay-a",
			Reason: string(rune('0' + index)),
		})
		if err != nil {
			t.Fatal(err)
		}
	}
	events, err := store.List(AuditFilter{RelayID: "relay-a", Limit: 3})
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 3 || events[0].Reason != "4" || events[2].Reason != "2" {
		t.Fatalf("newest audit events = %+v", events)
	}
}

func TestAuditConcurrentAppendDoesNotLoseRecords(t *testing.T) {
	store, err := NewAuditStore(t.TempDir(), 30)
	if err != nil {
		t.Fatal(err)
	}
	const writers = 20
	var group sync.WaitGroup
	group.Add(writers)
	for index := 0; index < writers; index++ {
		go func(index int) {
			defer group.Done()
			if _, err := store.Append(AuditEvent{
				Type: "session_connected", SessionID: fmt.Sprintf("session-%d", index),
			}); err != nil {
				t.Errorf("append %d: %v", index, err)
			}
		}(index)
	}
	group.Wait()
	events, err := store.List(AuditFilter{Limit: writers})
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != writers {
		t.Fatalf("concurrent audit records = %d, want %d", len(events), writers)
	}
}

func TestAuditListSkipsMalformedRecordsAndPreservesValidOnes(t *testing.T) {
	dir := t.TempDir()
	store, err := NewAuditStore(dir, 30)
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "srt-audit-"+time.Now().UTC().Format("2006-01-02")+".jsonl")
	if err := os.WriteFile(path, []byte("not-json\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Append(AuditEvent{Type: "session_connected", RelayID: "relay-a"}); err != nil {
		t.Fatal(err)
	}
	events, err := store.List(AuditFilter{Limit: 20})
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 1 || events[0].Type != "session_connected" {
		t.Fatalf("audit events after malformed record = %+v", events)
	}
}

func TestAuditListRejectsOversizedRecordWithoutUnboundedAllocation(t *testing.T) {
	dir := t.TempDir()
	store, err := NewAuditStore(dir, 30)
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "srt-audit-"+time.Now().UTC().Format("2006-01-02")+".jsonl")
	data := make([]byte, 1024*1024+1)
	for index := range data {
		data[index] = 'x'
	}
	if err := os.WriteFile(path, data, 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := store.List(AuditFilter{Limit: 20}); err == nil {
		t.Fatal("expected oversized audit record error")
	}
}

func TestAuditRetentionRemovesExpiredDailyFiles(t *testing.T) {
	dir := t.TempDir()
	store, err := NewAuditStore(dir, 7)
	if err != nil {
		t.Fatal(err)
	}
	old := time.Now().UTC().AddDate(0, 0, -30)
	if _, err := store.Append(AuditEvent{Time: old, Type: "old-event"}); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Append(AuditEvent{Time: time.Now().UTC(), Type: "current-event"}); err != nil {
		t.Fatal(err)
	}
	oldPath := filepath.Join(dir, "srt-audit-"+old.Format("2006-01-02")+".jsonl")
	if _, err := os.Stat(oldPath); !os.IsNotExist(err) {
		t.Fatalf("expired audit file still exists: %v", err)
	}
}

func TestAuditClearRemovesMatchingRecords(t *testing.T) {
	store, err := NewAuditStore(t.TempDir(), 30)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := store.Append(AuditEvent{Type: "session_connected", RelayID: "relay-a"}); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Append(AuditEvent{Type: "session_connected", RelayID: "relay-b"}); err != nil {
		t.Fatal(err)
	}
	cleared, err := store.Clear(AuditFilter{RelayID: "relay-a"})
	if err != nil {
		t.Fatal(err)
	}
	if cleared != 1 {
		t.Fatalf("cleared = %d, want 1", cleared)
	}
	events, err := store.List(AuditFilter{Limit: 20})
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 1 || events[0].RelayID != "relay-b" {
		t.Fatalf("remaining audit events = %+v", events)
	}
}

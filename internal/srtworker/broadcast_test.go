package srtworker

import (
	"errors"
	"sync"
	"testing"
	"time"

	"neotranscoder/internal/srtrelay"
)

func TestBroadcastDisconnectsPersistentlySlowClient(t *testing.T) {
	worker := &worker{
		config:   srtrelay.WorkerConfig{Relay: srtrelay.Relay{PayloadSize: 1316}},
		events:   make(chan srtrelay.WorkerEvent, 1024),
		sessions: make(map[string]*clientSession),
		send:     func(int, []byte, int) (int, error) { return 0, nil },
	}
	session := &clientSession{
		worker: worker, socket: -1,
		done: make(chan struct{}), data: srtrelay.Session{ID: "slow-session"},
	}
	worker.sessions[session.data.ID] = session
	packet := make([]byte, 1316)
	for index := 0; index < maxQueueDropBurst-1; index++ {
		worker.broadcast(packet)
	}
	select {
	case <-session.done:
		t.Fatal("client disconnected before the drop burst limit")
	default:
	}
	worker.broadcast(packet)

	select {
	case <-session.done:
	case <-time.After(time.Second):
		t.Fatal("slow client was not disconnected")
	}
	worker.mu.RLock()
	_, exists := worker.sessions[session.data.ID]
	worker.mu.RUnlock()
	if exists {
		t.Fatal("disconnected slow client remained in worker sessions")
	}
	if session.appDrops.Load() != maxQueueDropBurst {
		t.Fatalf("application drops = %d, want %d", session.appDrops.Load(), maxQueueDropBurst)
	}
	event := <-worker.events
	if event.Type != "session_disconnected" || event.Reason != "client send queue remained full" {
		t.Fatalf("disconnect event = %+v", event)
	}
}

func TestBroadcastClosesSessionOnSendError(t *testing.T) {
	worker := &worker{
		config:   srtrelay.WorkerConfig{Relay: srtrelay.Relay{PayloadSize: 1316}},
		events:   make(chan srtrelay.WorkerEvent, 10),
		sessions: make(map[string]*clientSession),
		send:     func(int, []byte, int) (int, error) { return 0, errors.New("connection lost") },
	}
	session := &clientSession{
		worker: worker, socket: -1,
		done: make(chan struct{}), data: srtrelay.Session{ID: "broken"},
	}
	worker.sessions[session.data.ID] = session
	worker.broadcast(make([]byte, 1316))
	select {
	case <-session.done:
	default:
		t.Fatal("session with failed send was not closed")
	}
	event := <-worker.events
	if event.Reason != "SRT send failed: connection lost" {
		t.Fatalf("disconnect reason = %q", event.Reason)
	}
	// Later broadcasts skip the closed session.
	worker.broadcast(make([]byte, 1316))
	if len(worker.events) != 0 {
		t.Fatal("closed session produced more events")
	}
}

func TestSessionCloseIsIdempotentUnderConcurrentFailures(t *testing.T) {
	worker := &worker{
		config:   srtrelay.WorkerConfig{Relay: srtrelay.Relay{PayloadSize: 1316}},
		events:   make(chan srtrelay.WorkerEvent, 10),
		sessions: make(map[string]*clientSession),
	}
	session := &clientSession{
		worker: worker, socket: -1,
		done: make(chan struct{}), data: srtrelay.Session{ID: "session-1"},
	}
	worker.sessions[session.data.ID] = session
	var group sync.WaitGroup
	group.Add(10)
	for index := 0; index < 10; index++ {
		go func() {
			defer group.Done()
			session.close("concurrent failure")
		}()
	}
	select {
	case <-session.done:
	case <-time.After(time.Second):
		t.Fatal("session did not close")
	}
	group.Wait()
	if got := len(worker.events); got != 1 {
		t.Fatalf("disconnect events = %d, want 1", got)
	}
}

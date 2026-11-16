package srtworker

import (
	"bytes"
	"net"
	"testing"
	"time"

	"neotranscoder/internal/srtrelay"
)

func TestBatchPreservesBytesBoundariesAndOwnership(t *testing.T) {
	const payload = 1316
	input := make([]byte, payload*25+97)
	for i := range input {
		input[i] = byte(i)
	}
	for _, chunk := range []int{1, 188, 1316, 1500, 65535} {
		b := newPacketBatcher(payload)
		var batches [][]byte
		emit := func(data []byte) { batches = append(batches, data) }
		for offset := 0; offset < len(input); {
			end := min(offset+chunk, len(input))
			b.append(input[offset:end], emit)
			b.flush(emit) // also exercise flushes while a payload is incomplete
			offset = end
		}
		for _, data := range batches {
			if len(data)%payload != 0 || len(data) > payload*sendBatchPackets {
				t.Fatalf("invalid batch size %d", len(data))
			}
		}
		if got := bytes.Join(batches, nil); !bytes.Equal(got, input[:payload*25]) {
			t.Fatalf("changed payload for chunk size %d", chunk)
		}
		if !bytes.Equal(b.pending, input[payload*25:]) {
			t.Fatal("lost partial payload")
		}
		// Reusing pending storage must not mutate data still queued for receivers.
		b.append(make([]byte, payload*sendBatchPackets), func([]byte) {})
		if !bytes.Equal(bytes.Join(batches, nil), input[:payload*25]) {
			t.Fatal("queued batch mutated")
		}
	}
}

func TestInputFlushesSparseTrafficAndStopsWithoutPackets(t *testing.T) {
	conn, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatal(err)
	}
	sender, err := net.DialUDP("udp4", nil, conn.LocalAddr().(*net.UDPAddr))
	if err != nil {
		conn.Close()
		t.Fatal(err)
	}
	defer sender.Close()
	w := &worker{input: conn, config: srtrelay.WorkerConfig{Relay: srtrelay.Relay{PayloadSize: 1316}}, sessions: make(map[string]*clientSession)}
	session := &clientSession{queue: make(chan []byte, sessionQueueSize), done: make(chan struct{})}
	w.sessions["receiver"] = session
	errors := make(chan error, 1)
	stopped := make(chan struct{})
	w.wg.Add(1)
	go func() { w.inputLoop(errors); close(stopped) }()
	defer func() {
		w.stopping.Store(true)
		conn.Close()
		select {
		case <-stopped:
		case <-time.After(time.Second):
			t.Error("input did not stop")
		}
	}()
	packet := bytes.Repeat([]byte{0x47}, 1316)
	for i := 0; i < 2; i++ {
		if _, err = sender.Write(packet); err != nil {
			t.Fatal(err)
		}
		select {
		case got := <-session.queue:
			session.queuedPackets.Add(-1)
			if !bytes.Equal(got, packet) {
				t.Fatal("sparse packet changed")
			}
		case err := <-errors:
			t.Fatal(err)
		case <-time.After(time.Second):
			t.Fatal("sparse packet not flushed without subsequent traffic")
		}
	}
	// An incomplete payload survives timeout and is combined with the next input.
	if _, err = sender.Write(packet[:188]); err != nil {
		t.Fatal(err)
	}
	time.Sleep(sendBatchDelay * 3)
	select {
	case <-session.queue:
		t.Fatal("partial SRT payload emitted")
	default:
	}
	if _, err = sender.Write(packet[188:]); err != nil {
		t.Fatal(err)
	}
	select {
	case got := <-session.queue:
		if !bytes.Equal(got, packet) {
			t.Fatal("partial payload corrupted")
		}
	case <-time.After(time.Second):
		t.Fatal("completed payload not flushed")
	}
}

func TestBatchQueueKeepsPacketLimitAndIsolatesSlowReceiver(t *testing.T) {
	w := &worker{config: srtrelay.WorkerConfig{Relay: srtrelay.Relay{PayloadSize: 1316}}, events: make(chan srtrelay.WorkerEvent, 10), sessions: make(map[string]*clientSession)}
	slow := &clientSession{worker: w, socket: -1, queue: make(chan []byte, sessionQueueSize), done: make(chan struct{}), data: srtrelay.Session{ID: "slow"}}
	fast := &clientSession{worker: w, socket: -1, queue: make(chan []byte, sessionQueueSize), done: make(chan struct{}), data: srtrelay.Session{ID: "fast"}}
	w.sessions["slow"], w.sessions["fast"] = slow, fast
	batch := make([]byte, 1316*sendBatchPackets)
	for i := 0; i < (sessionQueueSize+maxQueueDropBurst)/sendBatchPackets; i++ {
		w.broadcast(batch)
		select {
		case got := <-fast.queue:
			fast.queuedPackets.Add(-sendBatchPackets)
			if !bytes.Equal(got, batch) {
				t.Fatal("fast receiver corrupted")
			}
		default:
			t.Fatal("slow receiver blocked fast receiver")
		}
	}
	select {
	case <-slow.done:
	case <-time.After(time.Second):
		t.Fatal("slow receiver not closed")
	}
	if slow.queuedPackets.Load() != sessionQueueSize || len(slow.queue) != sessionQueueSize/sendBatchPackets {
		t.Fatal("queue packet ceiling changed")
	}
	if slow.appDrops.Load() != maxQueueDropBurst || fast.appDrops.Load() != 0 {
		t.Fatal("incorrect packet drop accounting")
	}
}

// This isolates packet preparation only; it is not a transport CPU benchmark.
func BenchmarkPacketPreparation(b *testing.B) {
	packet := make([]byte, 1316)
	var sink []byte
	b.Run("previous_per_packet", func(b *testing.B) {
		pending := make([]byte, 0, 2632)
		b.ReportAllocs()
		b.SetBytes(1316)
		for i := 0; i < b.N; i++ {
			pending = append(pending, packet...)
			sink = append([]byte(nil), pending[:1316]...)
			pending = pending[1316:]
		}
	})
	b.Run("batch_8", func(b *testing.B) {
		batch := newPacketBatcher(1316)
		emit := func(data []byte) { sink = data }
		b.ReportAllocs()
		b.SetBytes(1316)
		for i := 0; i < b.N; i++ {
			batch.append(packet, emit)
		}
		batch.flush(emit)
	})
	if len(sink) == 0 {
		b.Fatal("no output")
	}
}

package srtworker

import (
	"bytes"
	"net"
	"sync"
	"syscall"
	"testing"
	"time"

	"neotranscoder/internal/srtrelay"
)

func TestPayloadBufferPreservesBytesAndBoundaries(t *testing.T) {
	const payload = 1316
	input := make([]byte, payload*25+97)
	for i := range input {
		input[i] = byte(i)
	}
	for _, chunk := range []int{1, 188, 1316, 1500, 65535} {
		buffer := payloadBuffer{payloadSize: payload}
		var sent []byte
		for offset := 0; offset < len(input); {
			end := min(offset+chunk, len(input))
			buffer.write(input[offset:end])
			ready := buffer.ready()
			if len(ready)%payload != 0 {
				t.Fatalf("ready size %d is not whole payloads", len(ready))
			}
			sent = append(sent, ready...)
			buffer.consume(len(ready))
			offset = end
		}
		if !bytes.Equal(sent, input[:payload*25]) {
			t.Fatalf("changed payload for chunk size %d", chunk)
		}
		if !bytes.Equal(buffer.data, input[payload*25:]) {
			t.Fatalf("lost partial payload for chunk size %d", chunk)
		}
	}
}

type recordingSender struct {
	mu        sync.Mutex
	delivered chan []byte
	accept    map[int]func(total int) (int, error)
}

func (r *recordingSender) send(socket int, payloads []byte, payloadSize int) (int, error) {
	total := len(payloads) / payloadSize
	accepted := total
	var err error
	r.mu.Lock()
	if decide, ok := r.accept[socket]; ok {
		accepted, err = decide(total)
	}
	r.mu.Unlock()
	if err == nil && accepted > 0 && r.delivered != nil {
		r.delivered <- append([]byte(nil), payloads[:accepted*payloadSize]...)
	}
	return accepted, err
}

func TestInputLoopForwardsPayloadsAndStops(t *testing.T) {
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
	recorder := &recordingSender{delivered: make(chan []byte, 1024)}
	inputFD, err := detachFromPoller(conn)
	if err != nil {
		t.Fatal(err)
	}
	w := &worker{
		inputFD: inputFD, send: recorder.send,
		config:   srtrelay.WorkerConfig{Relay: srtrelay.Relay{PayloadSize: 1316}},
		sessions: map[string]*clientSession{"receiver": {socket: 1, done: make(chan struct{})}},
	}
	failures := make(chan error, 1)
	stopped := make(chan struct{})
	w.wg.Add(1)
	go func() { w.inputLoop(failures); close(stopped) }()
	defer func() {
		w.stopping.Store(true)
		select {
		case <-stopped:
			syscall.Close(inputFD)
		case <-time.After(time.Second):
			t.Error("input did not stop")
		}
	}()
	receive := func(want int) []byte {
		t.Helper()
		var got []byte
		deadline := time.After(2 * time.Second)
		for len(got) < want {
			select {
			case data := <-recorder.delivered:
				got = append(got, data...)
			case err := <-failures:
				t.Fatal(err)
			case <-deadline:
				t.Fatalf("received %d of %d bytes", len(got), want)
			}
		}
		return got
	}

	packet := bytes.Repeat([]byte{0x47}, 1316)
	for i := 0; i < 2; i++ {
		if _, err = sender.Write(packet); err != nil {
			t.Fatal(err)
		}
		if got := receive(len(packet)); !bytes.Equal(got, packet) {
			t.Fatal("sparse packet changed")
		}
	}

	// A burst larger than one recvmmsg batch arrives complete and in order.
	var burst []byte
	for i := 0; i < 40; i++ {
		datagram := bytes.Repeat([]byte{byte(i)}, 1316)
		burst = append(burst, datagram...)
		if _, err = sender.Write(datagram); err != nil {
			t.Fatal(err)
		}
	}
	if got := receive(len(burst)); !bytes.Equal(got, burst) {
		t.Fatal("burst changed or reordered")
	}

	// An incomplete payload waits for the rest of its bytes.
	if _, err = sender.Write(packet[:188]); err != nil {
		t.Fatal(err)
	}
	time.Sleep(inputPollInterval * 4)
	select {
	case <-recorder.delivered:
		t.Fatal("partial SRT payload emitted")
	default:
	}
	if _, err = sender.Write(packet[188:]); err != nil {
		t.Fatal(err)
	}
	if got := receive(len(packet)); !bytes.Equal(got, packet) {
		t.Fatal("partial payload corrupted")
	}
	if w.inputBytes.Load() != int64(2*len(packet)+len(burst)+len(packet)) {
		t.Fatalf("input bytes = %d", w.inputBytes.Load())
	}
}

func TestBroadcastIsolatesSlowReceiver(t *testing.T) {
	recorder := &recordingSender{accept: map[int]func(int) (int, error){
		1: func(int) (int, error) { return 0, nil },
	}}
	w := &worker{
		send:     recorder.send,
		config:   srtrelay.WorkerConfig{Relay: srtrelay.Relay{PayloadSize: 1316}},
		events:   make(chan srtrelay.WorkerEvent, 10),
		sessions: make(map[string]*clientSession),
	}
	slow := &clientSession{worker: w, socket: 1, done: make(chan struct{}), data: srtrelay.Session{ID: "slow"}}
	fast := &clientSession{worker: w, socket: 2, done: make(chan struct{}), data: srtrelay.Session{ID: "fast"}}
	w.sessions["slow"], w.sessions["fast"] = slow, fast
	const perBatch = 8
	batch := make([]byte, 1316*perBatch)
	for i := 0; i < maxQueueDropBurst/perBatch; i++ {
		w.broadcast(batch)
	}
	select {
	case <-slow.done:
	default:
		t.Fatal("slow receiver not closed")
	}
	select {
	case <-fast.done:
		t.Fatal("fast receiver closed")
	default:
	}
	if slow.appDrops.Load() != maxQueueDropBurst || fast.appDrops.Load() != 0 {
		t.Fatalf("drops slow=%d fast=%d", slow.appDrops.Load(), fast.appDrops.Load())
	}
}

func TestBroadcastFullAcceptResetsDropBurst(t *testing.T) {
	accepted := 4
	recorder := &recordingSender{accept: map[int]func(int) (int, error){
		1: func(int) (int, error) { return accepted, nil },
	}}
	w := &worker{
		send:     recorder.send,
		config:   srtrelay.WorkerConfig{Relay: srtrelay.Relay{PayloadSize: 1316}},
		events:   make(chan srtrelay.WorkerEvent, 10),
		sessions: make(map[string]*clientSession),
	}
	session := &clientSession{worker: w, socket: 1, done: make(chan struct{}), data: srtrelay.Session{ID: "s"}}
	w.sessions["s"] = session
	batch := make([]byte, 1316*8)
	w.broadcast(batch)
	if session.dropBurst.Load() != 4 || session.appDrops.Load() != 4 {
		t.Fatalf("partial accept: burst=%d drops=%d", session.dropBurst.Load(), session.appDrops.Load())
	}
	recorder.mu.Lock()
	accepted = 8
	recorder.mu.Unlock()
	w.broadcast(batch)
	if session.dropBurst.Load() != 0 || session.appDrops.Load() != 4 {
		t.Fatalf("full accept: burst=%d drops=%d", session.dropBurst.Load(), session.appDrops.Load())
	}
}

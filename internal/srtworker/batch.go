package srtworker

import "time"

const (
	sendBatchPackets = 8
	// ponytail: at most 5 ms of batching delay; keep SRT messages separate.
	// Larger groups reduce Go/C calls but increase delivery latency.
	sendBatchDelay = 5 * time.Millisecond
)

// packetBatcher owns its pending bytes. Emitted batches are immutable and may
// be shared by multiple session queues until their sends complete.
type packetBatcher struct {
	payloadSize int
	pending     []byte
}

func newPacketBatcher(payloadSize int) *packetBatcher {
	return &packetBatcher{payloadSize: payloadSize, pending: make([]byte, 0, payloadSize*sendBatchPackets)}
}

func (b *packetBatcher) append(data []byte, emit func([]byte)) {
	for len(data) > 0 {
		n := min(len(data), cap(b.pending)-len(b.pending))
		b.pending = append(b.pending, data[:n]...)
		data = data[n:]
		if len(b.pending) == cap(b.pending) {
			b.flush(emit)
		}
	}
}

func (b *packetBatcher) flush(emit func([]byte)) {
	n := len(b.pending) / b.payloadSize * b.payloadSize
	if n == 0 {
		return
	}
	emit(append([]byte(nil), b.pending[:n]...))
	remaining := copy(b.pending, b.pending[n:])
	b.pending = b.pending[:remaining]
}

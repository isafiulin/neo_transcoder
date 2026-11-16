package srtworker

import "time"

const (
	// inputPollInterval bounds the added delivery delay. Input is drained and
	// forwarded once per interval instead of waking up for every datagram.
	inputPollInterval = 5 * time.Millisecond
	// Soft cap per poll so a flooded input cannot starve shutdown checks.
	maxDatagramsPerPoll = 1024
)

// payloadBuffer accumulates multicast bytes and exposes whole SRT payloads.
type payloadBuffer struct {
	payloadSize int
	data        []byte
}

func (b *payloadBuffer) write(data []byte) {
	b.data = append(b.data, data...)
}

// ready returns all complete payloads. The slice is valid until the next
// write or consume.
func (b *payloadBuffer) ready() []byte {
	return b.data[:len(b.data)/b.payloadSize*b.payloadSize]
}

func (b *payloadBuffer) consume(n int) {
	b.data = b.data[:copy(b.data, b.data[n:])]
}

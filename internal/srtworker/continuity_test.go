package srtworker

import "testing"

func TestContinuityTracker(t *testing.T) {
	tracker := newContinuityTracker()
	packet := func(counter byte) []byte {
		data := make([]byte, 188)
		data[0] = 0x47
		data[1] = 0x01
		data[2] = 0x00
		data[3] = 0x10 | counter
		return data
	}
	if got := tracker.observe(packet(4)); got != 0 {
		t.Fatalf("first packet errors = %d", got)
	}
	if got := tracker.observe(packet(5)); got != 0 {
		t.Fatalf("sequential packet errors = %d", got)
	}
	if got := tracker.observe(packet(7)); got != 1 {
		t.Fatalf("gap errors = %d", got)
	}
}

func TestContinuityTrackerHandlesMalformedAndSpecialPackets(t *testing.T) {
	tracker := newContinuityTracker()
	packet := make([]byte, 188)
	if got := tracker.observe(packet); got != 1 {
		t.Fatalf("bad sync byte errors = %d", got)
	}
	if got := tracker.observe(make([]byte, 189)); got != 2 {
		t.Fatalf("unaligned malformed payload errors = %d", got)
	}

	nullPacket := make([]byte, 188)
	nullPacket[0], nullPacket[1], nullPacket[2], nullPacket[3] = 0x47, 0x1f, 0xff, 0x10
	if got := tracker.observe(nullPacket); got != 0 {
		t.Fatalf("null PID errors = %d", got)
	}

	adaptationOnly := make([]byte, 188)
	adaptationOnly[0], adaptationOnly[1], adaptationOnly[2], adaptationOnly[3] = 0x47, 0x01, 0x00, 0x20
	if got := tracker.observe(adaptationOnly); got != 0 {
		t.Fatalf("adaptation-only errors = %d", got)
	}

	discontinuity := make([]byte, 188)
	discontinuity[0], discontinuity[1], discontinuity[2], discontinuity[3] = 0x47, 0x01, 0x00, 0x37
	discontinuity[4], discontinuity[5] = 1, 0x80
	if got := tracker.observe(discontinuity); got != 0 {
		t.Fatalf("declared discontinuity errors = %d", got)
	}
}

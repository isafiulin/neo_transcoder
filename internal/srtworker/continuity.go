package srtworker

type continuityTracker struct {
	last map[uint16]byte
}

func newContinuityTracker() *continuityTracker {
	return &continuityTracker{last: make(map[uint16]byte)}
}

func (t *continuityTracker) observe(data []byte) int64 {
	var errors int64
	if len(data)%188 != 0 {
		errors++
	}
	for offset := 0; offset+188 <= len(data); offset += 188 {
		packet := data[offset : offset+188]
		if packet[0] != 0x47 {
			errors++
			continue
		}
		pid := uint16(packet[1]&0x1f)<<8 | uint16(packet[2])
		if pid == 0x1fff {
			continue
		}
		adaptationControl := (packet[3] >> 4) & 0x03
		if adaptationControl == 0 {
			errors++
			continue
		}
		hasPayload := adaptationControl == 1 || adaptationControl == 3
		if !hasPayload {
			continue
		}
		discontinuity := false
		if adaptationControl == 3 && packet[4] > 0 && int(packet[4])+5 <= len(packet) {
			discontinuity = packet[5]&0x80 != 0
		}
		counter := packet[3] & 0x0f
		if previous, ok := t.last[pid]; ok && !discontinuity && counter != (previous+1)&0x0f {
			errors++
		}
		t.last[pid] = counter
	}
	return errors
}

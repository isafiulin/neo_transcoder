package streams

import "testing"

func TestParseProgress(t *testing.T) {
	got := parseProgress(map[string]string{
		"frame":       "250",
		"fps":         "25.00",
		"bitrate":     "4000.0kbits/s",
		"total_size":  "123456",
		"out_time":    "00:00:10.000000",
		"out_time_ms": "10000000",
		"speed":       "1.00x",
		"progress":    "continue",
	})

	if got.Frame != 250 {
		t.Fatalf("frame = %d", got.Frame)
	}
	if got.FPS != 25 {
		t.Fatalf("fps = %f", got.FPS)
	}
	if got.Bitrate != "4000.0kbits/s" || got.Speed != "1.00x" {
		t.Fatalf("unexpected metrics: %+v", got)
	}
}

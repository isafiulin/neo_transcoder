package streams

import "testing"

func TestParseProcStatHandlesProcessNameWithSpaces(t *testing.T) {
	sample := "123 (ffmpeg worker) S 1 2 3 4 5 6 7 8 9 10 120 30 14 15 16 17 18 19 20 21 22 256"
	got, err := parseProcStat(sample, 4096)
	if err != nil {
		t.Fatal(err)
	}
	if got.cpuTicks != 150 {
		t.Fatalf("cpu ticks = %d", got.cpuTicks)
	}
	if got.rssBytes != 22*4096 {
		t.Fatalf("rss bytes = %d", got.rssBytes)
	}
}

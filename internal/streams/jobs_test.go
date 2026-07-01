package streams

import (
	"bufio"
	"strings"
	"testing"
)

func TestScanCRLFSplitsOnBareCR(t *testing.T) {
	// This is what ffmpeg's console stats line looks like on the wire: each
	// update overwrites the previous one with a bare \r, never a \n, until
	// the final update before the process exits (which does get a trailing
	// \n from the next real log line).
	input := "frame=   1 fps=25 bitrate= 100kbits/s\rframe=   2 fps=25 bitrate= 100kbits/s\r" +
		"[info] Stream mapping done\n"
	scanner := bufio.NewScanner(strings.NewReader(input))
	scanner.Split(scanCRLF)

	var tokens []string
	for scanner.Scan() {
		tokens = append(tokens, scanner.Text())
	}
	if err := scanner.Err(); err != nil {
		t.Fatal(err)
	}

	want := []string{
		"frame=   1 fps=25 bitrate= 100kbits/s",
		"frame=   2 fps=25 bitrate= 100kbits/s",
		"[info] Stream mapping done",
	}
	if len(tokens) != len(want) {
		t.Fatalf("got %d tokens, want %d: %#v", len(tokens), len(want), tokens)
	}
	for i, token := range tokens {
		if token != want[i] {
			t.Fatalf("token[%d] = %q, want %q", i, token, want[i])
		}
	}
}

func TestScanCRLFHandlesCRLF(t *testing.T) {
	scanner := bufio.NewScanner(strings.NewReader("one\r\ntwo\r\n"))
	scanner.Split(scanCRLF)

	var tokens []string
	for scanner.Scan() {
		tokens = append(tokens, scanner.Text())
	}
	if len(tokens) != 2 || tokens[0] != "one" || tokens[1] != "two" {
		t.Fatalf("unexpected tokens: %#v", tokens)
	}
}

func TestIsFFmpegStatsLine(t *testing.T) {
	statsLines := []string{
		"frame=   123 fps= 25 q=28.0 size=    2048kB time=00:00:49.32 bitrate= 340.2kbits/s speed=1.00x",
		"size=    1024kB time=00:00:10.00 bitrate= 838.8kbits/s speed=1.00x",
	}
	for _, line := range statsLines {
		if !isFFmpegStatsLine(line) {
			t.Fatalf("expected %q to be recognized as a stats line", line)
		}
	}

	notStats := []string{
		"[info] Stream mapping:",
		"[h264 @ 0x55e314ef6640] non-existing PPS 0 referenced",
		"frame size mismatch",
	}
	for _, line := range notStats {
		if isFFmpegStatsLine(line) {
			t.Fatalf("did not expect %q to be recognized as a stats line", line)
		}
	}
}

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

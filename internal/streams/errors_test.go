package streams

import (
	"strings"
	"testing"
)

func TestClassifyError(t *testing.T) {
	tests := map[string]string{
		"bind failed: Address already in use":       ErrorBind,
		"Network is unreachable":                    ErrorNetwork,
		"Unknown encoder 'libx264'":                 ErrorCodec,
		"Error opening input: No such file":         ErrorInput,
		"Error opening output udp://239.1.1.1:1234": ErrorOutput,
	}

	for input, want := range tests {
		if got := classifyError(input); got != want {
			t.Fatalf("classifyError(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestParseFFmpegLevel(t *testing.T) {
	tests := []struct {
		line        string
		wantLevel   string
		wantMessage string
	}{
		{
			line:        "[info] Stream mapping:",
			wantLevel:   "info",
			wantMessage: "Stream mapping:",
		},
		{
			// The component tag ("[h264 @ 0x...]") comes before the level
			// tag ffmpeg adds via -loglevel level+info, not after it.
			line:        "[h264 @ 0x55e314ef6640] [error] non-existing PPS 0 referenced",
			wantLevel:   "error",
			wantMessage: "[h264 @ 0x55e314ef6640] non-existing PPS 0 referenced",
		},
		{
			line:        "[h264 @ 0x55e314ef6640] [warning] some warning text",
			wantLevel:   "warn",
			wantMessage: "[h264 @ 0x55e314ef6640] some warning text",
		},
		{
			line:        "restart failed: exit status 1",
			wantLevel:   "info",
			wantMessage: "restart failed: exit status 1",
		},
	}

	for _, tc := range tests {
		level, message := parseFFmpegLevel(tc.line)
		if level != tc.wantLevel || message != tc.wantMessage {
			t.Fatalf("parseFFmpegLevel(%q) = (%q, %q), want (%q, %q)",
				tc.line, level, message, tc.wantLevel, tc.wantMessage)
		}
	}
}

func TestIsPacketLossNoise(t *testing.T) {
	noisy := []string{
		"[mpegts @ 0x55e314ece900] Packet corrupt",
		"[in#0/mpegts @ 0x55e314ece640] corrupt input packet in stream 0",
		"[aist#0:1/mp2 @ 0x55e314ef86c0] [warning] timestamp discontinuity (stream id=422): 12528000, new offset= -12528000",
		"[h264 @ 0x55e314f25b80] [error] error while decoding MB 71 14",
		"[vist#0:0/h264 @ 0x55e314ec6240] [dec:h264 @ 0x55e315088680] corrupt decoded frame",
		"[h264 @ 0x55e314ef6640] [error] non-existing PPS 0 referenced",
		"[h264 @ 0x55e314ef6640] [error] non-existing SPS 0 referenced",
		"[h264 @ 0x55e314ef6640] [error] decode_slice_header error",
		"[h264 @ 0x55e314ef6640] [error] no frame!",
		"[h264 @ 0x55e314efe240] [warning] co located POCs unavailable",
	}
	for _, line := range noisy {
		if !isPacketLossNoise(strings.ToLower(line)) {
			t.Fatalf("expected %q to be classified as packet loss noise", line)
		}
	}

	notNoise := []string{
		"bind failed: Address already in use",
		"Unknown encoder 'libx264'",
		"stream started",
	}
	for _, line := range notNoise {
		if isPacketLossNoise(strings.ToLower(line)) {
			t.Fatalf("did not expect %q to be classified as packet loss noise", line)
		}
	}
}

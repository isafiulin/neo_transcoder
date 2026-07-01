package streams

import (
	"regexp"
	"strings"
)

const (
	ErrorProcessExit = "process_exit"
	ErrorInput       = "input_error"
	ErrorOutput      = "output_error"
	ErrorBind        = "bind_error"
	ErrorNetwork     = "network_error"
	ErrorCodec       = "codec_error"
	ErrorPermission  = "permission_error"
	ErrorUnknown     = "unknown_error"
	// ErrorPacketLoss marks known-benign multicast packet-loss symptoms -
	// these are expected on real-world IPTV UDP feeds and are logged as a
	// warning, never escalated to an error or used to trigger a restart.
	ErrorPacketLoss = "packet_loss"
)

// isPacketLossNoise recognizes ffmpeg messages that are typical, expected
// fallout from a single lost or corrupt UDP packet, or from joining a
// multicast stream mid-GOP before its next SPS/PPS, on IPTV input. Unlike
// classifyError, this is a narrow positive-match allowlist (not a catch-all
// default), so it can safely be checked unconditionally, ahead of - and
// regardless of - whatever severity tag ffmpeg itself put on the line.
//
// "non-existing PPS/SPS referenced" and "decode_slice_header error"/"no
// frame!" are grouped here (rather than under classifyError's codec_error)
// because they share the same root cause as the others: a decoder that
// hasn't yet seen a keyframe/parameter set, not a genuine encode/decode
// failure. It can't be fixed from this side - only reduced by a cleaner
// source feed - so it's demoted to a warning instead of paging as an error.
func isPacketLossNoise(lower string) bool {
	return strings.Contains(lower, "packet corrupt") ||
		strings.Contains(lower, "corrupt input packet") ||
		strings.Contains(lower, "timestamp discontinuity") ||
		strings.Contains(lower, "error while decoding mb") ||
		strings.Contains(lower, "corrupt decoded frame") ||
		strings.Contains(lower, "non-existing pps") ||
		strings.Contains(lower, "non-existing sps") ||
		strings.Contains(lower, "decode_slice_header error") ||
		strings.Contains(lower, "no frame!") ||
		strings.Contains(lower, "co located pocs unavailable")
}

// isFFmpegStatsLine recognizes ffmpeg's own console stats line (enabled
// per-stream via Config.KeepStats, off by default in favor of -progress
// pipe:1). It's rewritten in place with a bare \r and never a trailing \n,
// repeating roughly once per -stats_period, so logging every occurrence
// would flood the store with a near-duplicate entry every second forever.
// -progress pipe:1 already exposes the same frame/fps/bitrate/speed numbers
// structured (see captureProgress/parseProgress in jobs.go), so these are
// recognized and discarded rather than stored.
func isFFmpegStatsLine(line string) bool {
	trimmed := strings.TrimSpace(line)
	return (strings.HasPrefix(trimmed, "frame=") || strings.HasPrefix(trimmed, "size=")) &&
		strings.Contains(trimmed, "bitrate=")
}

func classifyError(message string) string {
	lower := strings.ToLower(message)
	switch {
	case lower == "":
		return ""
	case strings.Contains(lower, "permission denied") || strings.Contains(lower, "operation not permitted"):
		return ErrorPermission
	case strings.Contains(lower, "address already in use") || strings.Contains(lower, "bind failed"):
		return ErrorBind
	case strings.Contains(lower, "no route to host") ||
		strings.Contains(lower, "network is unreachable") ||
		strings.Contains(lower, "connection refused") ||
		strings.Contains(lower, "connection timed out"):
		return ErrorNetwork
	case strings.Contains(lower, "invalid data found") ||
		strings.Contains(lower, "could not find codec") ||
		strings.Contains(lower, "unknown decoder") ||
		strings.Contains(lower, "unknown encoder") ||
		strings.Contains(lower, "error while decoding") ||
		strings.Contains(lower, "error while encoding"):
		return ErrorCodec
	case strings.Contains(lower, "error opening input") ||
		strings.Contains(lower, "no such file or directory") ||
		strings.Contains(lower, "input/output error"):
		return ErrorInput
	case strings.Contains(lower, "error opening output") ||
		strings.Contains(lower, "muxer") ||
		strings.Contains(lower, "could not write"):
		return ErrorOutput
	default:
		return ErrorUnknown
	}
}

var ffmpegLevelTag = regexp.MustCompile(`\[(panic|fatal|error|warning|info|verbose|debug|trace)\]\s*`)

// parseFFmpegLevel reads the "[level]" tag ffmpeg adds to every line when run
// with -loglevel level+info (see ffmpeg/args.go) and returns our own level
// string plus the line with the tag stripped. The tag is NOT necessarily at
// the start of the line: ffmpeg prints its own "[component @ 0x...]" prefix
// first (e.g. "[h264 @ 0x...]"), then the "[level]" tag, then the message -
// so this searches the whole line for the first level tag rather than
// anchoring at position 0. Lines without a recognized tag (e.g.
// NeoTranscoder's own generated messages) default to "info", since the tag -
// not keyword guessing - is the ground truth for severity.
func parseFFmpegLevel(line string) (level string, message string) {
	loc := ffmpegLevelTag.FindStringSubmatchIndex(line)
	if loc == nil {
		return "info", line
	}
	message = line[:loc[0]] + line[loc[1]:]
	switch line[loc[2]:loc[3]] {
	case "panic", "fatal", "error":
		return "error", message
	case "warning":
		return "warn", message
	default:
		return "info", message
	}
}

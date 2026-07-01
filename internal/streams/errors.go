package streams

import "strings"

const (
	ErrorProcessExit = "process_exit"
	ErrorInput       = "input_error"
	ErrorOutput      = "output_error"
	ErrorBind        = "bind_error"
	ErrorNetwork     = "network_error"
	ErrorCodec       = "codec_error"
	ErrorPermission  = "permission_error"
	ErrorUnknown     = "unknown_error"
)

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

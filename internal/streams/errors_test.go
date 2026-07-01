package streams

import "testing"

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

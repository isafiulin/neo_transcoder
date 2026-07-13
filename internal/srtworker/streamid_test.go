package srtworker

import "testing"

func TestClientIDFromStreamID(t *testing.T) {
	tests := map[string]string{
		"partner-a":                           "partner-a",
		"#!::r=news-hd,u=partner-a,m=request": "partner-a",
		"#!::u=partner%2Da,r=news-hd":         "partner-a",
	}
	for input, expected := range tests {
		actual, err := clientIDFromStreamID(input)
		if err != nil {
			t.Fatalf("%q: %v", input, err)
		}
		if actual != expected {
			t.Fatalf("%q: got %q, want %q", input, actual, expected)
		}
	}
	invalid := []string{
		"", "#!::r=news-hd,m=request", "#!::u=", "#!::u=%zz",
	}
	for _, input := range invalid {
		if _, err := clientIDFromStreamID(input); err == nil {
			t.Fatalf("expected Stream ID %q error", input)
		}
	}
}

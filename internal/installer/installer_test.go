package installer

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPromptPortDefaultsOnEmptyInput(t *testing.T) {
	got, err := promptPort(strings.NewReader("\n"), &bytes.Buffer{}, 8080)
	if err != nil {
		t.Fatal(err)
	}
	if got != 8080 {
		t.Fatalf("port = %d, want 8080", got)
	}
}

func TestPromptPortAcceptsCustomPort(t *testing.T) {
	got, err := promptPort(strings.NewReader("18080\n"), &bytes.Buffer{}, 8080)
	if err != nil {
		t.Fatal(err)
	}
	if got != 18080 {
		t.Fatalf("port = %d, want 18080", got)
	}
}

func TestPromptPortRetriesInvalidInput(t *testing.T) {
	var output bytes.Buffer
	got, err := promptPort(strings.NewReader("not-a-port\n70000\n18080\n"), &output, 8080)
	if err != nil {
		t.Fatal(err)
	}
	if got != 18080 || strings.Count(output.String(), "Port must be") != 2 {
		t.Fatalf("port=%d output=%q", got, output.String())
	}
}

func TestPromptPortRejectsInvalidEOF(t *testing.T) {
	if _, err := promptPort(strings.NewReader("70000"), &bytes.Buffer{}, 8080); err == nil {
		t.Fatal("expected invalid EOF port error")
	}
}

func TestValidatePortBoundaries(t *testing.T) {
	for _, port := range []int{1, 65535} {
		if err := validatePort(port); err != nil {
			t.Fatalf("valid port %d rejected: %v", port, err)
		}
	}
	for _, port := range []int{0, -1, 65536} {
		if err := validatePort(port); err == nil {
			t.Fatalf("invalid port %d accepted", port)
		}
	}
}

func TestCopyFileSetsExecutableMode(t *testing.T) {
	dir := t.TempDir()
	source := filepath.Join(dir, "source")
	target := filepath.Join(dir, "target")
	if err := os.WriteFile(source, []byte("#!/bin/sh\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := copyFile(source, target, 0o755); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(target)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o755 {
		t.Fatalf("mode = %o, want 755", info.Mode().Perm())
	}
}

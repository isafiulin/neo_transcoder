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

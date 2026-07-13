package main

import (
	"log/slog"
	"path/filepath"
	"testing"

	"neotranscoder/internal/config"
)

func TestRunRejectsUnknownAndMalformedCommands(t *testing.T) {
	if code := run([]string{"unknown"}); code != 2 {
		t.Fatalf("unknown command code = %d", code)
	}
	if code := run([]string{"config"}); code != 2 {
		t.Fatalf("empty config command code = %d", code)
	}
	if code := run([]string{"doctor", "--bad-flag"}); code != 2 {
		t.Fatalf("bad doctor flag code = %d", code)
	}
}

func TestConfigCLIWriteSetAndValidate(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	if code := runConfig([]string{"write-default", "--config", path}); code != 0 {
		t.Fatalf("write-default code = %d", code)
	}
	if code := runConfig([]string{"set-server", "--config", path, "--bind", "127.0.0.1", "--port", "18080"}); code != 0 {
		t.Fatalf("set-server code = %d", code)
	}
	if code := runConfig([]string{"validate", "--config", path}); code != 0 {
		t.Fatalf("validate code = %d", code)
	}
	cfg, err := config.Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Server.Bind != "127.0.0.1" || cfg.Server.Port != 18080 {
		t.Fatalf("server config = %+v", cfg.Server)
	}
	if code := runConfig([]string{"set-server", "--config", path, "--port", "70000"}); code != 1 {
		t.Fatalf("invalid set-server code = %d", code)
	}
}

func TestParseLevel(t *testing.T) {
	tests := map[string]slog.Level{
		"debug": slog.LevelDebug, "warning": slog.LevelWarn,
		"warn": slog.LevelWarn, "error": slog.LevelError, "other": slog.LevelInfo,
	}
	for input, expected := range tests {
		if got := parseLevel(input); got != expected {
			t.Fatalf("parseLevel(%q) = %v, want %v", input, got, expected)
		}
	}
}

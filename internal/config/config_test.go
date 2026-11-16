package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDefaultConfigIsValid(t *testing.T) {
	if err := Default().Validate(); err != nil {
		t.Fatal(err)
	}
}

func TestConfigRejectsInvalidPort(t *testing.T) {
	cfg := Default()
	cfg.Server.Port = 70000
	if err := cfg.Validate(); err == nil {
		t.Fatal("expected invalid port error")
	}
}

func TestConfigRejectsInvalidRequiredAndSRTFields(t *testing.T) {
	tests := map[string]func(*Config){
		"bind":            func(cfg *Config) { cfg.Server.Bind = "all" },
		"worker":          func(cfg *Config) { cfg.SRT.WorkerPath = "" },
		"SRT state":       func(cfg *Config) { cfg.SRT.StatePath = "" },
		"SRT master key":  func(cfg *Config) { cfg.SRT.MasterKeyPath = "" },
		"SRT audit":       func(cfg *Config) { cfg.SRT.AuditDir = "" },
		"audit retention": func(cfg *Config) { cfg.SRT.AuditRetentionDays = 0 },
		"storage":         func(cfg *Config) { cfg.Storage.Path = "" },
		"log level":       func(cfg *Config) { cfg.Logs.Level = "" },
	}
	for name, mutate := range tests {
		t.Run(name, func(t *testing.T) {
			cfg := Default()
			mutate(&cfg)
			if err := cfg.Validate(); err == nil {
				t.Fatal("expected validation error")
			}
		})
	}
}

func TestLegacyEncoderConfigIsIgnored(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	data := []byte(`{"ffmpeg":{"path":"","ffprobe_path":""},"server":{"bind":"127.0.0.1","port":9090},"srt":{"state_path":"/data/existing-srt.json","master_key_path":"/data/existing.key"}}`)
	if err := os.WriteFile(path, data, 0600); err != nil {
		t.Fatal(err)
	}
	cfg, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Server.Port != 9090 || cfg.SRT.StatePath != "/data/existing-srt.json" || cfg.SRT.MasterKeyPath != "/data/existing.key" {
		t.Fatalf("legacy settings changed: %+v", cfg)
	}
}

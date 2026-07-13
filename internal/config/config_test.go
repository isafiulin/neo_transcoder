package config

import "testing"

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
		"ffmpeg":          func(cfg *Config) { cfg.FFmpeg.Path = "" },
		"ffprobe":         func(cfg *Config) { cfg.FFmpeg.FFprobePath = "" },
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

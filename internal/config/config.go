package config

import (
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
)

const DefaultPath = "/etc/neotranscoder/config.json"

type Config struct {
	Server  ServerConfig  `json:"server"`
	FFmpeg  FFmpegConfig  `json:"ffmpeg"`
	Storage StorageConfig `json:"storage"`
	Logs    LogsConfig    `json:"logs"`
}

type ServerConfig struct {
	Bind string `json:"bind"`
	Port int    `json:"port"`
}

type FFmpegConfig struct {
	Path        string `json:"path"`
	FFprobePath string `json:"ffprobe_path"`
}

type StorageConfig struct {
	Path string `json:"path"`
}

type LogsConfig struct {
	Level string `json:"level"`
	Path  string `json:"path"`
}

func Default() Config {
	return Config{
		Server: ServerConfig{
			Bind: "0.0.0.0",
			Port: 8080,
		},
		FFmpeg: FFmpegConfig{
			Path:        "/usr/bin/ffmpeg",
			FFprobePath: "/usr/bin/ffprobe",
		},
		Storage: StorageConfig{
			Path: "/var/lib/neotranscoder/state.json",
		},
		Logs: LogsConfig{
			Level: "info",
			Path:  "/var/log/neotranscoder/neotranscoder.log",
		},
	}
}

func Load(path string) (Config, error) {
	cfg := Default()
	if path == "" {
		path = DefaultPath
	}

	data, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return cfg, nil
		}
		return Config{}, err
	}
	if err := json.Unmarshal(data, &cfg); err != nil {
		return Config{}, fmt.Errorf("parse config %s: %w", path, err)
	}
	return cfg, cfg.Validate()
}

func (c Config) Validate() error {
	if c.Server.Port < 1 || c.Server.Port > 65535 {
		return fmt.Errorf("server.port must be between 1 and 65535")
	}
	if net.ParseIP(c.Server.Bind) == nil {
		return fmt.Errorf("server.bind must be an IP address")
	}
	if c.FFmpeg.Path == "" {
		return fmt.Errorf("ffmpeg.path is required")
	}
	if c.FFmpeg.FFprobePath == "" {
		return fmt.Errorf("ffmpeg.ffprobe_path is required")
	}
	if c.Storage.Path == "" {
		return fmt.Errorf("storage.path is required")
	}
	if c.Logs.Level == "" {
		return fmt.Errorf("logs.level is required")
	}
	return nil
}

func (c Config) Addr() string {
	return fmt.Sprintf("%s:%d", c.Server.Bind, c.Server.Port)
}

func WriteDefault(path string) error {
	if path == "" {
		path = DefaultPath
	}
	return Write(path, Default())
}

func Write(path string, cfg Config) error {
	if path == "" {
		path = DefaultPath
	}
	if err := cfg.Validate(); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	return os.WriteFile(path, data, 0o644)
}

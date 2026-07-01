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

// FFmpegConfig holds ffmpeg tuning that is system-level, not per-stream: it
// hardens the process against real-world IPTV multicast conditions (dropped
// or corrupt UDP packets) and is deliberately kept out of encoding profiles,
// which only expose codec/bitrate/preset-style user-facing settings.
type FFmpegConfig struct {
	Path        string `json:"path"`
	FFprobePath string `json:"ffprobe_path"`

	UDPFifoSize        int  `json:"udp_fifo_size,omitempty"`
	UDPBufferSize      int  `json:"udp_buffer_size,omitempty"`
	UDPOverrunNonfatal bool `json:"udp_overrun_nonfatal,omitempty"`
	UDPReuse           bool `json:"udp_reuse,omitempty"`
	AnalyzeDuration    int  `json:"analyzeduration,omitempty"`
	ProbeSize          int  `json:"probesize,omitempty"`
	Threads            int  `json:"threads,omitempty"`
	PktSize            int  `json:"pkt_size,omitempty"`
	DiscardCorrupt     bool `json:"discard_corrupt,omitempty"`
	// LogLevel is the ffmpeg severity floor (info/warning/error/...), always
	// combined with the "level" flag (see ffmpeg.SystemConfig /
	// BuildArgs) so log lines keep their "[level]" tag for classification.
	// Defaults to "warning" so routine per-stream info banners (mapping,
	// codec details) aren't written to the log at all; set to "info" to get
	// that detail back for troubleshooting.
	LogLevel string `json:"log_level,omitempty"`
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
			Path:               "/usr/bin/ffmpeg",
			FFprobePath:        "/usr/bin/ffprobe",
			UDPFifoSize:        100000000,
			UDPBufferSize:      8388608,
			UDPOverrunNonfatal: true,
			UDPReuse:           true,
			AnalyzeDuration:    10000000,
			ProbeSize:          20000000,
			Threads:            2,
			PktSize:            1316,
			DiscardCorrupt:     true,
			LogLevel:           "warning",
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

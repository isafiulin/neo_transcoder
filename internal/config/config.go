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

// FFmpegConfig holds ffmpeg tuning that is system-level, not per-stream: UDP
// transport resilience for multicast input/output. These are safe by
// construction - they don't touch encoding, GOP, or error tolerance, so they
// can't change bitrate or picture quality, unlike the encode-affecting flags
// that used to live here (-fflags/-err_detect/-g/-keyint_min/-sc_threshold/
// -threads). Those are now opt-in per profile - see ffmpeg.AdvancedProfile -
// because enabling them by default changed encoder behavior and output
// bitrate in ways operators didn't ask for.
type FFmpegConfig struct {
	Path        string `json:"path"`
	FFprobePath string `json:"ffprobe_path"`
	// LogLevel is the ffmpeg severity floor (info/warning/error/...), always
	// combined with the "level" flag (see ffmpeg.SystemConfig /
	// BuildArgs) so log lines keep their "[level]" tag for classification.
	// Defaults to "warning" so routine per-stream info banners (mapping,
	// codec details) aren't written to the log at all; set to "info" to get
	// that detail back for troubleshooting.
	LogLevel string      `json:"log_level,omitempty"`
	UDP      UDPConfig   `json:"udp,omitempty"`
	Probe    ProbeConfig `json:"probe,omitempty"`
}

// UDPConfig hardens UDP multicast transport only - buffering, packet reuse,
// and output packet size. None of it affects the encoder.
type UDPConfig struct {
	BufferSize      int  `json:"buffer_size,omitempty"`
	FifoSize        int  `json:"fifo_size,omitempty"`
	OverrunNonfatal bool `json:"overrun_nonfatal,omitempty"`
	Reuse           bool `json:"reuse,omitempty"`
	PktSize         int  `json:"pkt_size,omitempty"`
}

// ProbeConfig only affects how long/how much ffmpeg looks at the input
// before starting - not the encode itself.
type ProbeConfig struct {
	AnalyzeDuration int `json:"analyzeduration,omitempty"`
	ProbeSize       int `json:"probesize,omitempty"`
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
			LogLevel:    "warning",
			UDP: UDPConfig{
				BufferSize:      8388608,
				FifoSize:        100000000,
				OverrunNonfatal: true,
				Reuse:           true,
				PktSize:         1316,
			},
			Probe: ProbeConfig{
				AnalyzeDuration: 10000000,
				ProbeSize:       20000000,
			},
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

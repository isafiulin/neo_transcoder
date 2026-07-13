package srtrelay

import "time"

type WorkerConfig struct {
	Relay             Relay          `json:"relay"`
	PublishPassphrase string         `json:"publish_passphrase,omitempty"`
	Clients           []WorkerClient `json:"clients,omitempty"`
}

type WorkerClient struct {
	ID             string   `json:"id"`
	EncryptionMode string   `json:"encryption_mode"`
	Passphrase     string   `json:"passphrase,omitempty"`
	AllowedCIDRs   []string `json:"allowed_cidrs"`
	MaxSessions    int      `json:"max_sessions"`
}

type WorkerEvent struct {
	Type             string    `json:"type"`
	Time             time.Time `json:"time"`
	Reason           string    `json:"reason,omitempty"`
	Session          *Session  `json:"session,omitempty"`
	ActiveClients    int       `json:"active_clients,omitempty"`
	InputBitrateBPS  int64     `json:"input_bitrate_bps,omitempty"`
	OutputBitrateBPS int64     `json:"output_bitrate_bps,omitempty"`
	InputPackets     int64     `json:"input_packets,omitempty"`
	ContinuityErrors int64     `json:"continuity_errors,omitempty"`
}

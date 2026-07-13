package srtrelay

import "time"

const (
	EncryptionAES256  = "aes-256"
	EncryptionNone    = "none"
	DirectionListener = "listener"
	DirectionPublish  = "publish"
)

type Relay struct {
	ID                   string `json:"id"`
	Name                 string `json:"name"`
	Direction            string `json:"direction"`
	InputURL             string `json:"input_url"`
	NetworkInterface     string `json:"network_interface,omitempty"`
	BindAddress          string `json:"bind_address"`
	Port                 int    `json:"port"`
	DestinationAddress   string `json:"destination_address,omitempty"`
	DestinationPort      int    `json:"destination_port,omitempty"`
	StreamID             string `json:"stream_id,omitempty"`
	EncryptionMode       string `json:"encryption_mode,omitempty"`
	KeyVersion           int    `json:"key_version,omitempty"`
	LatencyMS            int    `json:"latency_ms"`
	PayloadSize          int    `json:"payload_size"`
	MaxClients           int    `json:"max_clients"`
	InputTimeoutSeconds  int    `json:"input_timeout_seconds"`
	AllowMissingStreamID bool   `json:"allow_missing_stream_id,omitempty"`
	DefaultClientID      string `json:"default_client_id,omitempty"`
	Enabled              bool   `json:"enabled"`
}

type RelayState struct {
	Status           string    `json:"status"`
	PID              int       `json:"pid,omitempty"`
	ActiveClients    int       `json:"active_clients"`
	InputBitrateBPS  int64     `json:"input_bitrate_bps"`
	OutputBitrateBPS int64     `json:"output_bitrate_bps"`
	InputPackets     int64     `json:"input_packets"`
	ContinuityErrors int64     `json:"continuity_errors"`
	RestartCount     int       `json:"restart_count"`
	Flapping         bool      `json:"flapping"`
	LastError        string    `json:"last_error,omitempty"`
	UpdatedAt        time.Time `json:"updated_at"`
}

type RelayView struct {
	Config     Relay      `json:"config"`
	State      RelayState `json:"state"`
	Passphrase string     `json:"passphrase,omitempty"`
}

type Client struct {
	ID              string    `json:"id"`
	Name            string    `json:"name"`
	Enabled         bool      `json:"enabled"`
	EncryptionMode  string    `json:"encryption_mode"`
	AllowedRelayIDs []string  `json:"allowed_relay_ids"`
	AllowedCIDRs    []string  `json:"allowed_cidrs"`
	MaxSessions     int       `json:"max_sessions"`
	KeyVersion      int       `json:"key_version"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
}

type ClientCredential struct {
	Client     Client `json:"client"`
	Passphrase string `json:"passphrase,omitempty"`
}

type SessionStats struct {
	BytesSent       int64   `json:"bytes_sent"`
	PacketsSent     int64   `json:"packets_sent"`
	PacketsLost     int64   `json:"packets_lost"`
	PacketsRetrans  int64   `json:"packets_retransmitted"`
	PacketsDropped  int64   `json:"packets_dropped"`
	BitrateBPS      int64   `json:"bitrate_bps"`
	RTTMilliseconds float64 `json:"rtt_ms"`
	LatencyMS       int     `json:"latency_ms"`
}

type Session struct {
	ID               string       `json:"id"`
	RelayID          string       `json:"relay_id"`
	ClientID         string       `json:"client_id"`
	RemoteIP         string       `json:"remote_ip"`
	RemotePort       int          `json:"remote_port"`
	StreamID         string       `json:"stream_id"`
	PeerVersion      string       `json:"peer_version,omitempty"`
	Encrypted        bool         `json:"encrypted"`
	ConnectedAt      time.Time    `json:"connected_at"`
	DisconnectedAt   *time.Time   `json:"disconnected_at,omitempty"`
	DisconnectReason string       `json:"disconnect_reason,omitempty"`
	Stats            SessionStats `json:"stats"`
}

type AuditEvent struct {
	ID         string         `json:"id"`
	Time       time.Time      `json:"time"`
	Type       string         `json:"type"`
	Level      string         `json:"level"`
	RelayID    string         `json:"relay_id,omitempty"`
	ClientID   string         `json:"client_id,omitempty"`
	SessionID  string         `json:"session_id,omitempty"`
	RemoteIP   string         `json:"remote_ip,omitempty"`
	RemotePort int            `json:"remote_port,omitempty"`
	StreamID   string         `json:"stream_id,omitempty"`
	Reason     string         `json:"reason,omitempty"`
	Actor      string         `json:"actor,omitempty"`
	Details    map[string]any `json:"details,omitempty"`
}

type Event struct {
	Type     string    `json:"type"`
	RelayID  string    `json:"relay_id,omitempty"`
	ClientID string    `json:"client_id,omitempty"`
	Time     time.Time `json:"time"`
	Payload  any       `json:"payload,omitempty"`
}

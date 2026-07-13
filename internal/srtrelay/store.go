package srtrelay

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

var idPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9_.-]{2,63}$`)

type Store struct {
	mu          sync.RWMutex
	path        string
	masterKey   []byte
	relays      map[string]Relay
	states      map[string]RelayState
	clients     map[string]Client
	sessions    map[string]Session
	audit       *AuditStore
	subscribers map[chan Event]struct{}
}

type persistedState struct {
	Relays  []Relay  `json:"relays"`
	Clients []Client `json:"clients"`
}

func NewStore(statePath, masterKeyPath, auditDir string, auditRetentionDays int) (*Store, error) {
	masterKey, err := loadOrCreateMasterKey(masterKeyPath)
	if err != nil {
		return nil, fmt.Errorf("SRT master key: %w", err)
	}
	audit, err := NewAuditStore(auditDir, auditRetentionDays)
	if err != nil {
		return nil, fmt.Errorf("SRT audit: %w", err)
	}
	store := &Store{
		path:        statePath,
		masterKey:   masterKey,
		relays:      make(map[string]Relay),
		states:      make(map[string]RelayState),
		clients:     make(map[string]Client),
		sessions:    make(map[string]Session),
		audit:       audit,
		subscribers: make(map[chan Event]struct{}),
	}
	if err := store.load(); err != nil {
		return nil, err
	}
	return store, nil
}

func (s *Store) ListRelays() []RelayView {
	s.mu.RLock()
	defer s.mu.RUnlock()
	ids := sortedKeys(s.relays)
	out := make([]RelayView, 0, len(ids))
	for _, id := range ids {
		out = append(out, RelayView{Config: s.relays[id], State: s.stateLocked(id)})
	}
	return out
}

func (s *Store) GetRelay(id string) (RelayView, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	relay, ok := s.relays[id]
	if !ok {
		return RelayView{}, false
	}
	return RelayView{Config: relay, State: s.stateLocked(id)}, true
}

func (s *Store) UpsertRelay(relay Relay) (RelayView, error) {
	normalized, err := normalizeRelay(relay)
	if err != nil {
		return RelayView{}, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	existing, exists := s.relays[normalized.ID]
	if exists {
		normalized.KeyVersion = existing.KeyVersion
	}
	for id, existing := range s.relays {
		if normalized.Direction == DirectionListener && existing.Direction == DirectionListener && id != normalized.ID && existing.BindAddress == normalized.BindAddress && existing.Port == normalized.Port {
			return RelayView{}, fmt.Errorf("SRT listener %s:%d is already used by relay %q", normalized.BindAddress, normalized.Port, id)
		}
	}
	if err := s.validateRelayDefaultClientLocked(normalized); err != nil {
		return RelayView{}, err
	}
	issuesCredential := !exists && normalized.Direction == DirectionPublish && normalized.EncryptionMode == EncryptionAES256
	if normalized.Direction == DirectionPublish && normalized.EncryptionMode == EncryptionAES256 &&
		(exists && (existing.Direction != DirectionPublish || existing.EncryptionMode != EncryptionAES256)) {
		normalized.KeyVersion++
		issuesCredential = true
	}
	s.relays[normalized.ID] = normalized
	if _, ok := s.states[normalized.ID]; !ok {
		s.states[normalized.ID] = RelayState{Status: "stopped", UpdatedAt: time.Now().UTC()}
	}
	if err := s.saveLocked(); err != nil {
		return RelayView{}, err
	}
	view := RelayView{Config: normalized, State: s.states[normalized.ID]}
	if issuesCredential {
		view.Passphrase = s.relayPassphraseLocked(normalized)
	}
	s.emitLocked(Event{Type: "srt_relay_saved", RelayID: normalized.ID, Time: time.Now().UTC(), Payload: view})
	return view, nil
}

func (s *Store) PublishPassphrase(id string) string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	relay, ok := s.relays[id]
	if !ok || relay.Direction != DirectionPublish || relay.EncryptionMode != EncryptionAES256 {
		return ""
	}
	return s.relayPassphraseLocked(relay)
}

func (s *Store) DeleteRelay(id string) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.relays[id]; !ok {
		return false, nil
	}
	status := s.stateLocked(id).Status
	if status != "stopped" && status != "error" && status != "flapping" {
		return false, fmt.Errorf("relay must be stopped before deletion")
	}
	for _, client := range s.clients {
		if contains(client.AllowedRelayIDs, id) {
			return false, fmt.Errorf("relay is assigned to client %q", client.ID)
		}
	}
	delete(s.relays, id)
	delete(s.states, id)
	if err := s.saveLocked(); err != nil {
		return false, err
	}
	s.emitLocked(Event{Type: "srt_relay_deleted", RelayID: id, Time: time.Now().UTC()})
	return true, nil
}

func (s *Store) ListClients() []Client {
	s.mu.RLock()
	defer s.mu.RUnlock()
	ids := sortedKeys(s.clients)
	out := make([]Client, 0, len(ids))
	for _, id := range ids {
		out = append(out, s.clients[id])
	}
	return out
}

func (s *Store) GetClient(id string) (Client, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	client, ok := s.clients[id]
	return client, ok
}

func (s *Store) UpsertClient(client Client) (ClientCredential, error) {
	now := time.Now().UTC()
	s.mu.Lock()
	defer s.mu.Unlock()
	existing, exists := s.clients[client.ID]
	if exists {
		client.CreatedAt = existing.CreatedAt
		client.KeyVersion = existing.KeyVersion
	} else {
		client.CreatedAt = now
		client.KeyVersion = 1
	}
	client.UpdatedAt = now
	normalized, err := s.normalizeClientLocked(client)
	if err != nil {
		return ClientCredential{}, err
	}
	for _, relay := range s.relays {
		if relay.AllowMissingStreamID && relay.DefaultClientID == normalized.ID &&
			(!normalized.Enabled || !contains(normalized.AllowedRelayIDs, relay.ID)) {
			return ClientCredential{}, fmt.Errorf("client is the compatibility default for relay %q and must remain enabled and assigned", relay.ID)
		}
	}
	issuesCredential := !exists && normalized.EncryptionMode == EncryptionAES256
	if exists && existing.EncryptionMode == EncryptionNone && normalized.EncryptionMode == EncryptionAES256 {
		normalized.KeyVersion++
		issuesCredential = true
	}
	s.clients[normalized.ID] = normalized
	if err := s.saveLocked(); err != nil {
		return ClientCredential{}, err
	}
	s.emitLocked(Event{Type: "srt_client_saved", ClientID: normalized.ID, Time: now, Payload: normalized})
	credential := ClientCredential{Client: normalized}
	if issuesCredential {
		credential.Passphrase = s.passphraseLocked(normalized)
	}
	return credential, nil
}

func (s *Store) RotateClientKey(id string) (ClientCredential, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	client, ok := s.clients[id]
	if !ok {
		return ClientCredential{}, fmt.Errorf("SRT client not found")
	}
	if client.EncryptionMode == EncryptionNone {
		return ClientCredential{}, fmt.Errorf("SRT client encryption is disabled")
	}
	client.KeyVersion++
	client.UpdatedAt = time.Now().UTC()
	s.clients[id] = client
	if err := s.saveLocked(); err != nil {
		return ClientCredential{}, err
	}
	s.emitLocked(Event{Type: "srt_client_key_rotated", ClientID: id, Time: client.UpdatedAt, Payload: client})
	return ClientCredential{Client: client, Passphrase: s.passphraseLocked(client)}, nil
}

func (s *Store) DeleteClient(id string) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.clients[id]; !ok {
		return false, nil
	}
	for _, relay := range s.relays {
		if relay.AllowMissingStreamID && relay.DefaultClientID == id {
			return false, fmt.Errorf("client is the compatibility default for relay %q", relay.ID)
		}
	}
	for _, session := range s.sessions {
		if session.ClientID == id && session.DisconnectedAt == nil {
			return false, fmt.Errorf("client has an active SRT session")
		}
	}
	delete(s.clients, id)
	if err := s.saveLocked(); err != nil {
		return false, err
	}
	s.emitLocked(Event{Type: "srt_client_deleted", ClientID: id, Time: time.Now().UTC()})
	return true, nil
}

func (s *Store) WorkerClients(relayID string) []WorkerClient {
	s.mu.RLock()
	defer s.mu.RUnlock()
	ids := sortedKeys(s.clients)
	out := make([]WorkerClient, 0, len(ids))
	for _, id := range ids {
		client := s.clients[id]
		if !client.Enabled || !contains(client.AllowedRelayIDs, relayID) {
			continue
		}
		workerClient := WorkerClient{
			ID:             client.ID,
			EncryptionMode: client.EncryptionMode,
			AllowedCIDRs:   append([]string(nil), client.AllowedCIDRs...),
			MaxSessions:    client.MaxSessions,
		}
		if client.EncryptionMode == EncryptionAES256 {
			workerClient.Passphrase = s.passphraseLocked(client)
		}
		out = append(out, workerClient)
	}
	return out
}

func (s *Store) ListSessions(activeOnly bool) []Session {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]Session, 0, len(s.sessions))
	for _, session := range s.sessions {
		if activeOnly && session.DisconnectedAt != nil {
			continue
		}
		out = append(out, session)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ConnectedAt.After(out[j].ConnectedAt) })
	return out
}

func (s *Store) Audit(filter AuditFilter) ([]AuditEvent, error) {
	return s.audit.List(filter)
}

func (s *Store) RecordAudit(event AuditEvent) (AuditEvent, error) {
	stored, err := s.audit.Append(event)
	if err != nil {
		return AuditEvent{}, err
	}
	s.mu.Lock()
	s.emitLocked(Event{Type: "srt_audit", RelayID: stored.RelayID, ClientID: stored.ClientID, Time: stored.Time, Payload: stored})
	s.mu.Unlock()
	return stored, nil
}

func (s *Store) UpdateState(id string, update func(RelayState) RelayState) RelayState {
	s.mu.Lock()
	defer s.mu.Unlock()
	next := update(s.stateLocked(id))
	next.UpdatedAt = time.Now().UTC()
	s.states[id] = next
	s.emitLocked(Event{Type: "srt_relay_state", RelayID: id, Time: next.UpdatedAt, Payload: next})
	return next
}

func (s *Store) ApplyWorkerEvent(relayID string, event WorkerEvent) {
	now := event.Time
	if now.IsZero() {
		now = time.Now().UTC()
	}
	s.mu.Lock()
	inputTransition := ""
	session := Session{}
	if event.Session != nil {
		session = *event.Session
	}
	switch event.Type {
	case "relay_ready":
		state := s.stateLocked(relayID)
		state.Status = "running"
		state.LastError = ""
		state.UpdatedAt = now
		s.states[relayID] = state
	case "relay_metrics":
		state := s.stateLocked(relayID)
		state.ActiveClients = event.ActiveClients
		state.InputBitrateBPS = event.InputBitrateBPS
		state.OutputBitrateBPS = event.OutputBitrateBPS
		state.InputPackets = event.InputPackets
		state.ContinuityErrors = event.ContinuityErrors
		if event.Reason != "" && state.Status != "degraded" {
			state.Status = "degraded"
			state.LastError = event.Reason
			inputTransition = "input_stalled"
		} else if event.Reason == "" && state.Status == "degraded" {
			state.Status = "running"
			state.LastError = ""
			inputTransition = "input_restored"
		}
		state.UpdatedAt = now
		s.states[relayID] = state
	case "session_connected":
		if event.Session != nil {
			s.sessions[session.ID] = session
		}
	case "session_stats":
		if current, ok := s.sessions[session.ID]; ok {
			current.Stats = session.Stats
			s.sessions[session.ID] = current
		}
	case "session_disconnected":
		if event.Session != nil {
			s.sessions[session.ID] = session
		}
		s.pruneSessionsLocked()
	case "relay_error":
		state := s.stateLocked(relayID)
		state.Status = "error"
		state.LastError = event.Reason
		state.UpdatedAt = now
		s.states[relayID] = state
	}
	payload := any(event)
	if state, ok := s.states[relayID]; ok && (event.Type == "relay_ready" || event.Type == "relay_metrics" || event.Type == "relay_error") {
		payload = state
	}
	s.emitLocked(Event{Type: "srt_" + event.Type, RelayID: relayID, ClientID: session.ClientID, Time: now, Payload: payload})
	s.mu.Unlock()

	if auditEvent, ok := auditFromWorkerEvent(relayID, event, now); ok {
		_, _ = s.RecordAudit(auditEvent)
	}
	if inputTransition != "" {
		level := "info"
		if inputTransition == "input_stalled" {
			level = "warning"
		}
		_, _ = s.RecordAudit(AuditEvent{
			Time: now, Type: inputTransition, Level: level,
			RelayID: relayID, Reason: event.Reason,
		})
	}
}

func (s *Store) pruneSessionsLocked() {
	const maxCompletedSessions = 1000
	completed := make([]Session, 0, len(s.sessions))
	for _, session := range s.sessions {
		if session.DisconnectedAt != nil {
			completed = append(completed, session)
		}
	}
	if len(completed) <= maxCompletedSessions {
		return
	}
	sort.Slice(completed, func(i, j int) bool {
		return completed[i].DisconnectedAt.After(*completed[j].DisconnectedAt)
	})
	for _, session := range completed[maxCompletedSessions:] {
		delete(s.sessions, session.ID)
	}
}

func (s *Store) Subscribe(ctx context.Context) <-chan Event {
	ch := make(chan Event, 64)
	s.mu.Lock()
	s.subscribers[ch] = struct{}{}
	s.mu.Unlock()
	go func() {
		<-ctx.Done()
		s.mu.Lock()
		delete(s.subscribers, ch)
		close(ch)
		s.mu.Unlock()
	}()
	return ch
}

func (s *Store) stateLocked(id string) RelayState {
	if state, ok := s.states[id]; ok {
		return state
	}
	return RelayState{Status: "stopped", UpdatedAt: time.Now().UTC()}
}

func (s *Store) emitLocked(event Event) {
	for subscriber := range s.subscribers {
		select {
		case subscriber <- event:
		default:
		}
	}
}

func (s *Store) normalizeClientLocked(client Client) (Client, error) {
	if !idPattern.MatchString(client.ID) {
		return Client{}, fmt.Errorf("id must be 3-64 letters, numbers, dots, underscores or hyphens")
	}
	if strings.TrimSpace(client.Name) == "" {
		client.Name = client.ID
	}
	if client.EncryptionMode == "" {
		client.EncryptionMode = EncryptionAES256
	}
	if client.EncryptionMode != EncryptionAES256 && client.EncryptionMode != EncryptionNone {
		return Client{}, fmt.Errorf("encryption_mode must be %q or %q", EncryptionAES256, EncryptionNone)
	}
	if len(client.AllowedRelayIDs) == 0 {
		return Client{}, fmt.Errorf("at least one allowed relay is required")
	}
	seenRelays := make(map[string]struct{}, len(client.AllowedRelayIDs))
	for _, relayID := range client.AllowedRelayIDs {
		relay, ok := s.relays[relayID]
		if !ok {
			return Client{}, fmt.Errorf("relay %q not found", relayID)
		}
		if relay.Direction != DirectionListener {
			return Client{}, fmt.Errorf("relay %q does not accept listener clients", relayID)
		}
		seenRelays[relayID] = struct{}{}
	}
	client.AllowedRelayIDs = client.AllowedRelayIDs[:0]
	for relayID := range seenRelays {
		client.AllowedRelayIDs = append(client.AllowedRelayIDs, relayID)
	}
	sort.Strings(client.AllowedRelayIDs)
	if len(client.AllowedCIDRs) == 0 {
		return Client{}, fmt.Errorf("at least one allowed IP or CIDR is required")
	}
	for index, value := range client.AllowedCIDRs {
		normalized, err := normalizeCIDR(value)
		if err != nil {
			return Client{}, fmt.Errorf("allowed_cidrs[%d]: %w", index, err)
		}
		if client.EncryptionMode == EncryptionNone && unrestrictedCIDR(normalized) {
			return Client{}, fmt.Errorf("allowed_cidrs[%d]: unrestricted networks are forbidden without encryption", index)
		}
		client.AllowedCIDRs[index] = normalized
	}
	sort.Strings(client.AllowedCIDRs)
	if client.MaxSessions == 0 {
		client.MaxSessions = 1
	}
	if client.MaxSessions < 1 || client.MaxSessions > 1000 {
		return Client{}, fmt.Errorf("max_sessions must be between 1 and 1000")
	}
	if client.KeyVersion < 1 {
		client.KeyVersion = 1
	}
	return client, nil
}

func unrestrictedCIDR(value string) bool {
	_, network, err := net.ParseCIDR(value)
	if err != nil {
		return false
	}
	ones, _ := network.Mask.Size()
	return ones == 0
}

func normalizeRelay(relay Relay) (Relay, error) {
	if !idPattern.MatchString(relay.ID) {
		return Relay{}, fmt.Errorf("id must be 3-64 letters, numbers, dots, underscores or hyphens")
	}
	if strings.TrimSpace(relay.Name) == "" {
		relay.Name = relay.ID
	}
	if relay.Direction == "" {
		relay.Direction = DirectionListener
	}
	if relay.Direction != DirectionListener && relay.Direction != DirectionPublish {
		return Relay{}, fmt.Errorf("direction must be %q or %q", DirectionListener, DirectionPublish)
	}
	u, err := url.Parse(relay.InputURL)
	if err != nil || u.Scheme != "udp" || u.Host == "" {
		return Relay{}, fmt.Errorf("input_url must be a udp:// multicast MPEG-TS URL")
	}
	host := net.ParseIP(u.Hostname())
	if host == nil || !host.IsMulticast() {
		return Relay{}, fmt.Errorf("input_url host must be a multicast IP address")
	}
	if _, err := strconv.Atoi(u.Port()); err != nil {
		return Relay{}, fmt.Errorf("input_url must include a valid port")
	}
	if relay.Direction == DirectionPublish {
		relay.AllowMissingStreamID = false
		relay.DefaultClientID = ""
		if net.ParseIP(relay.DestinationAddress) == nil {
			return Relay{}, fmt.Errorf("destination_address must be an IP address")
		}
		if relay.DestinationPort < 1 || relay.DestinationPort > 65535 {
			return Relay{}, fmt.Errorf("destination_port must be between 1 and 65535")
		}
		if strings.TrimSpace(relay.StreamID) == "" || len(relay.StreamID) > 512 || strings.ContainsAny(relay.StreamID, "\r\n\x00") {
			return Relay{}, fmt.Errorf("stream_id must be 1-512 safe characters")
		}
		if relay.EncryptionMode == "" {
			relay.EncryptionMode = EncryptionAES256
		}
		if relay.EncryptionMode != EncryptionAES256 && relay.EncryptionMode != EncryptionNone {
			return Relay{}, fmt.Errorf("encryption_mode must be %q or %q", EncryptionAES256, EncryptionNone)
		}
		if relay.KeyVersion < 1 {
			relay.KeyVersion = 1
		}
	} else {
		if relay.BindAddress == "" {
			relay.BindAddress = "0.0.0.0"
		}
		if relay.AllowMissingStreamID {
			relay.DefaultClientID = strings.TrimSpace(relay.DefaultClientID)
			if !idPattern.MatchString(relay.DefaultClientID) {
				return Relay{}, fmt.Errorf("default_client_id must identify a valid SRT client")
			}
		} else {
			relay.DefaultClientID = ""
		}
	}
	if relay.Direction == DirectionListener && net.ParseIP(relay.BindAddress) == nil {
		return Relay{}, fmt.Errorf("bind_address must be an IP address")
	}
	if relay.Direction == DirectionListener && (relay.Port < 1 || relay.Port > 65535) {
		return Relay{}, fmt.Errorf("port must be between 1 and 65535")
	}
	if relay.LatencyMS == 0 {
		relay.LatencyMS = 800
	}
	if relay.LatencyMS < 20 || relay.LatencyMS > 60000 {
		return Relay{}, fmt.Errorf("latency_ms must be between 20 and 60000")
	}
	if relay.PayloadSize == 0 {
		relay.PayloadSize = 1316
	}
	if relay.PayloadSize < 188 || relay.PayloadSize > 1456 || relay.PayloadSize%188 != 0 {
		return Relay{}, fmt.Errorf("payload_size must be a multiple of 188 between 188 and 1456")
	}
	if relay.MaxClients == 0 {
		relay.MaxClients = 16
	}
	if relay.MaxClients < 1 || relay.MaxClients > 1000 {
		return Relay{}, fmt.Errorf("max_clients must be between 1 and 1000")
	}
	if relay.InputTimeoutSeconds == 0 {
		relay.InputTimeoutSeconds = 10
	}
	if relay.InputTimeoutSeconds < 3 || relay.InputTimeoutSeconds > 300 {
		return Relay{}, fmt.Errorf("input_timeout_seconds must be between 3 and 300")
	}
	return relay, nil
}

func (s *Store) relayPassphraseLocked(relay Relay) string {
	mac := hmac.New(sha256.New, s.masterKey)
	fmt.Fprintf(mac, "neotranscoder-srt-publish:%s:%d", relay.ID, relay.KeyVersion)
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func (s *Store) validateRelayDefaultClientLocked(relay Relay) error {
	if !relay.AllowMissingStreamID {
		return nil
	}
	client, ok := s.clients[relay.DefaultClientID]
	if !ok {
		return fmt.Errorf("default SRT client %q not found", relay.DefaultClientID)
	}
	if !client.Enabled {
		return fmt.Errorf("default SRT client %q is disabled", relay.DefaultClientID)
	}
	if !contains(client.AllowedRelayIDs, relay.ID) {
		return fmt.Errorf("default SRT client %q is not assigned to relay %q", relay.DefaultClientID, relay.ID)
	}
	return nil
}

func normalizeCIDR(value string) (string, error) {
	value = strings.TrimSpace(value)
	if ip := net.ParseIP(value); ip != nil {
		if ip.To4() != nil {
			return ip.String() + "/32", nil
		}
		return ip.String() + "/128", nil
	}
	_, network, err := net.ParseCIDR(value)
	if err != nil {
		return "", fmt.Errorf("must be an IP address or CIDR")
	}
	return network.String(), nil
}

func (s *Store) passphraseLocked(client Client) string {
	mac := hmac.New(sha256.New, s.masterKey)
	fmt.Fprintf(mac, "neotranscoder-srt:%s:%d", client.ID, client.KeyVersion)
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func (s *Store) load() error {
	if s.path == "" {
		return nil
	}
	data, err := os.ReadFile(s.path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	var state persistedState
	if err := json.Unmarshal(data, &state); err != nil {
		return fmt.Errorf("parse SRT state %s: %w", s.path, err)
	}
	for _, relay := range state.Relays {
		normalized, err := normalizeRelay(relay)
		if err != nil {
			return fmt.Errorf("relay %q: %w", relay.ID, err)
		}
		s.relays[normalized.ID] = normalized
		s.states[normalized.ID] = RelayState{Status: "stopped", UpdatedAt: time.Now().UTC()}
	}
	for _, client := range state.Clients {
		normalized, err := s.normalizeClientLocked(client)
		if err != nil {
			return fmt.Errorf("SRT client %q: %w", client.ID, err)
		}
		s.clients[normalized.ID] = normalized
	}
	for _, relay := range s.relays {
		if err := s.validateRelayDefaultClientLocked(relay); err != nil {
			return fmt.Errorf("relay %q: %w", relay.ID, err)
		}
	}
	return nil
}

func (s *Store) saveLocked() error {
	if s.path == "" {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(s.path), 0o750); err != nil {
		return err
	}
	state := persistedState{}
	for _, id := range sortedKeys(s.relays) {
		state.Relays = append(state.Relays, s.relays[id])
	}
	for _, id := range sortedKeys(s.clients) {
		state.Clients = append(state.Clients, s.clients[id])
	}
	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	tmp, err := os.CreateTemp(filepath.Dir(s.path), ".srt-state-*.tmp")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Chmod(tmpName, 0o600); err != nil {
		return err
	}
	return os.Rename(tmpName, s.path)
}

func loadOrCreateMasterKey(path string) ([]byte, error) {
	if path == "" {
		return nil, fmt.Errorf("path is required")
	}
	data, err := os.ReadFile(path)
	if err == nil {
		decoded, err := base64.RawURLEncoding.DecodeString(strings.TrimSpace(string(data)))
		if err != nil || len(decoded) != 32 {
			return nil, fmt.Errorf("invalid master key")
		}
		return decoded, nil
	}
	if !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		return nil, err
	}
	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		return nil, err
	}
	encoded := []byte(base64.RawURLEncoding.EncodeToString(key) + "\n")
	tmp, err := os.CreateTemp(filepath.Dir(path), ".srt-key-*.tmp")
	if err != nil {
		return nil, err
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	if _, err := tmp.Write(encoded); err != nil {
		_ = tmp.Close()
		return nil, err
	}
	if err := tmp.Close(); err != nil {
		return nil, err
	}
	if err := os.Chmod(tmpName, 0o600); err != nil {
		return nil, err
	}
	if err := os.Rename(tmpName, path); err != nil {
		return nil, err
	}
	return key, nil
}

func auditFromWorkerEvent(relayID string, event WorkerEvent, now time.Time) (AuditEvent, bool) {
	switch event.Type {
	case "connection_attempt", "connection_rejected", "session_connected", "session_disconnected", "relay_error":
	default:
		return AuditEvent{}, false
	}
	level := "info"
	if event.Type == "connection_rejected" || event.Type == "relay_error" {
		level = "warning"
	}
	session := Session{}
	if event.Session != nil {
		session = *event.Session
	}
	return AuditEvent{
		Time:       now,
		Type:       event.Type,
		Level:      level,
		RelayID:    relayID,
		ClientID:   session.ClientID,
		SessionID:  session.ID,
		RemoteIP:   session.RemoteIP,
		RemotePort: session.RemotePort,
		StreamID:   session.StreamID,
		Reason:     event.Reason,
		Details: map[string]any{
			"peer_version": session.PeerVersion,
			"encrypted":    session.Encrypted,
			"stats":        session.Stats,
		},
	}, true
}

func sortedKeys[T any](items map[string]T) []string {
	keys := make([]string, 0, len(items))
	for key := range items {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

func contains(items []string, value string) bool {
	for _, item := range items {
		if item == value {
			return true
		}
	}
	return false
}

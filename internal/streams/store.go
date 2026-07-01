package streams

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"

	"neotranscoder/internal/ffmpeg"
)

type Config struct {
	ID          string         `json:"id"`
	Name        string         `json:"name"`
	InputURL    string         `json:"input_url"`
	OutputURL   string         `json:"output_url"`
	ProfileName string         `json:"profile_name"`
	VideoMap    string         `json:"video_map,omitempty"`
	AudioMap    string         `json:"audio_map,omitempty"`
	Enabled     bool           `json:"enabled"`
	Restart     *RestartPolicy `json:"restart,omitempty"`
}

type RestartPolicy struct {
	Enabled        bool `json:"enabled"`
	MaxAttempts    int  `json:"max_attempts"`
	WindowSeconds  int  `json:"window_seconds"`
	BackoffSeconds int  `json:"backoff_seconds"`
}

type State struct {
	Status       string     `json:"status"`
	PID          int        `json:"pid,omitempty"`
	StartedAt    *time.Time `json:"started_at,omitempty"`
	StoppedAt    *time.Time `json:"stopped_at,omitempty"`
	ErrorCode    string     `json:"error_code,omitempty"`
	LastError    string     `json:"last_error,omitempty"`
	RestartCount int        `json:"restart_count"`
	Flapping     bool       `json:"flapping"`
	Metrics      *Metrics   `json:"metrics,omitempty"`
	Process      *Process   `json:"process,omitempty"`
}

type Metrics struct {
	Frame     int64     `json:"frame,omitempty"`
	FPS       float64   `json:"fps,omitempty"`
	Bitrate   string    `json:"bitrate,omitempty"`
	TotalSize int64     `json:"total_size,omitempty"`
	OutTime   string    `json:"out_time,omitempty"`
	OutTimeMS int64     `json:"out_time_ms,omitempty"`
	Speed     string    `json:"speed,omitempty"`
	Progress  string    `json:"progress,omitempty"`
	UpdatedAt time.Time `json:"updated_at"`
}

type Process struct {
	CPUPercent  float64   `json:"cpu_percent"`
	MemoryBytes int64     `json:"memory_bytes"`
	UpdatedAt   time.Time `json:"updated_at"`
}

type Event struct {
	Type     string    `json:"type"`
	StreamID string    `json:"stream_id,omitempty"`
	Time     time.Time `json:"time"`
	Payload  any       `json:"payload,omitempty"`
}

type LogEntry struct {
	StreamID string    `json:"stream_id"`
	Time     time.Time `json:"time"`
	Level    string    `json:"level"`
	Code     string    `json:"code,omitempty"`
	Message  string    `json:"message"`
}

type View struct {
	Config Config `json:"config"`
	State  State  `json:"state"`
}

type Store struct {
	mu          sync.RWMutex
	path        string
	streams     map[string]Config
	profiles    map[string]ffmpeg.Profile
	states      map[string]State
	logs        []LogEntry
	subscribers map[chan Event]struct{}
}

func NewStore(path string) (*Store, error) {
	store := &Store{
		path:        path,
		streams:     make(map[string]Config),
		profiles:    make(map[string]ffmpeg.Profile),
		states:      make(map[string]State),
		logs:        make([]LogEntry, 0, 512),
		subscribers: make(map[chan Event]struct{}),
	}
	if err := store.load(); err != nil {
		return nil, err
	}
	store.ensureDefaultProfiles()
	return store, nil
}

func (s *Store) List() []View {
	s.mu.RLock()
	defer s.mu.RUnlock()

	ids := make([]string, 0, len(s.streams))
	for id := range s.streams {
		ids = append(ids, id)
	}
	sort.Strings(ids)

	out := make([]View, 0, len(ids))
	for _, id := range ids {
		out = append(out, View{Config: s.streams[id], State: s.stateLocked(id)})
	}
	return out
}

func (s *Store) Metrics() []View {
	return s.List()
}

func (s *Store) Get(id string) (View, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	cfg, ok := s.streams[id]
	if !ok {
		return View{}, false
	}
	return View{Config: cfg, State: s.stateLocked(id)}, true
}

func (s *Store) Upsert(cfg Config) (View, error) {
	normalized, err := normalizeConfig(cfg)
	if err != nil {
		return View{}, err
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.profiles[normalized.ProfileName]; !ok {
		return View{}, fmt.Errorf("profile %q not found", normalized.ProfileName)
	}
	s.streams[normalized.ID] = normalized
	if _, ok := s.states[normalized.ID]; !ok {
		s.states[normalized.ID] = State{Status: "stopped"}
	}
	if err := s.saveLocked(); err != nil {
		return View{}, err
	}
	view := View{Config: normalized, State: s.states[normalized.ID]}
	s.emitLocked(Event{Type: "stream_saved", StreamID: normalized.ID, Time: time.Now(), Payload: view})
	return view, nil
}

func (s *Store) ListProfiles() []ffmpeg.Profile {
	s.mu.RLock()
	defer s.mu.RUnlock()

	names := make([]string, 0, len(s.profiles))
	for name := range s.profiles {
		names = append(names, name)
	}
	sort.Strings(names)

	out := make([]ffmpeg.Profile, 0, len(names))
	for _, name := range names {
		out = append(out, s.profiles[name])
	}
	return out
}

func (s *Store) GetProfile(name string) (ffmpeg.Profile, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	profile, ok := s.profiles[name]
	return profile, ok
}

func (s *Store) UpsertProfile(profile ffmpeg.Profile) (ffmpeg.Profile, error) {
	normalized, err := normalizeProfile(profile)
	if err != nil {
		return ffmpeg.Profile{}, err
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	s.profiles[normalized.Name] = normalized
	if err := s.saveLocked(); err != nil {
		return ffmpeg.Profile{}, err
	}
	s.emitLocked(Event{Type: "profile_saved", Time: time.Now(), Payload: normalized})
	return normalized, nil
}

func (s *Store) DeleteProfile(name string) (bool, error) {
	if name == "h264_veryfast_4m" {
		return false, fmt.Errorf("default profile cannot be deleted")
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.profiles[name]; !ok {
		return false, nil
	}
	for _, stream := range s.streams {
		if stream.ProfileName == name {
			return false, fmt.Errorf("profile is used by stream %q", stream.ID)
		}
	}
	delete(s.profiles, name)
	if err := s.saveLocked(); err != nil {
		return false, err
	}
	s.emitLocked(Event{Type: "profile_deleted", Time: time.Now(), Payload: map[string]string{"name": name}})
	return true, nil
}

func (s *Store) Delete(id string) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.streams[id]; !ok {
		return false, nil
	}
	delete(s.streams, id)
	delete(s.states, id)
	if err := s.saveLocked(); err != nil {
		return false, err
	}
	s.emitLocked(Event{Type: "stream_deleted", StreamID: id, Time: time.Now()})
	return true, nil
}

func (s *Store) SetState(id string, state State) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.states[id] = state
	s.emitLocked(Event{Type: "stream_state", StreamID: id, Time: time.Now(), Payload: state})
}

func (s *Store) UpdateState(id string, update func(State) State) State {
	s.mu.Lock()
	defer s.mu.Unlock()
	next := update(s.stateLocked(id))
	s.states[id] = next
	s.emitLocked(Event{Type: "stream_state", StreamID: id, Time: time.Now(), Payload: next})
	return next
}

func (s *Store) AppendLog(streamID, level, message string) {
	s.AppendLogCode(streamID, level, "", message)
}

func (s *Store) AppendLogCode(streamID, level, code, message string) {
	entry := LogEntry{
		StreamID: streamID,
		Time:     time.Now(),
		Level:    level,
		Code:     code,
		Message:  message,
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	s.logs = append(s.logs, entry)
	if len(s.logs) > 1000 {
		s.logs = s.logs[len(s.logs)-1000:]
	}
	s.emitLocked(Event{Type: "stream_log", StreamID: streamID, Time: entry.Time, Payload: entry})
}

func (s *Store) Logs(streamID string, limit int) []LogEntry {
	if limit <= 0 || limit > 500 {
		limit = 200
	}

	s.mu.RLock()
	defer s.mu.RUnlock()

	out := make([]LogEntry, 0, limit)
	for i := len(s.logs) - 1; i >= 0 && len(out) < limit; i-- {
		entry := s.logs[i]
		if streamID == "" || entry.StreamID == streamID {
			out = append(out, entry)
		}
	}
	for i, j := 0, len(out)-1; i < j; i, j = i+1, j-1 {
		out[i], out[j] = out[j], out[i]
	}
	return out
}

func (s *Store) Subscribe(ctx context.Context) <-chan Event {
	ch := make(chan Event, 32)

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

func (s *Store) stateLocked(id string) State {
	if state, ok := s.states[id]; ok {
		return state
	}
	return State{Status: "stopped"}
}

func (s *Store) emitLocked(event Event) {
	for ch := range s.subscribers {
		select {
		case ch <- event:
		default:
		}
	}
}

type persistedState struct {
	Streams  []Config         `json:"streams"`
	Profiles []ffmpeg.Profile `json:"profiles"`
}

func (s *Store) load() error {
	if s.path == "" {
		return nil
	}
	data, err := os.ReadFile(s.path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		return err
	}
	var state persistedState
	if err := json.Unmarshal(data, &state); err != nil {
		return fmt.Errorf("parse stream state %s: %w", s.path, err)
	}
	for _, profile := range state.Profiles {
		normalized, err := normalizeProfile(profile)
		if err != nil {
			return fmt.Errorf("profile %q: %w", profile.Name, err)
		}
		s.profiles[normalized.Name] = normalized
	}
	s.ensureDefaultProfiles()
	for _, cfg := range state.Streams {
		normalized, err := normalizeConfig(cfg)
		if err != nil {
			return fmt.Errorf("stream %q: %w", cfg.ID, err)
		}
		if _, ok := s.profiles[normalized.ProfileName]; !ok {
			return fmt.Errorf("stream %q: profile %q not found", normalized.ID, normalized.ProfileName)
		}
		s.streams[normalized.ID] = normalized
		s.states[normalized.ID] = State{Status: "stopped"}
	}
	return nil
}

func (s *Store) saveLocked() error {
	if s.path == "" {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(s.path), 0o755); err != nil {
		return err
	}
	ids := make([]string, 0, len(s.streams))
	for id := range s.streams {
		ids = append(ids, id)
	}
	sort.Strings(ids)

	state := persistedState{
		Streams:  make([]Config, 0, len(ids)),
		Profiles: s.sortedProfilesLocked(),
	}
	for _, id := range ids {
		state.Streams = append(state.Streams, s.streams[id])
	}
	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')

	tmp, err := os.CreateTemp(filepath.Dir(s.path), ".state-*.tmp")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		_ = os.Remove(tmpName)
		return err
	}
	if err := tmp.Close(); err != nil {
		_ = os.Remove(tmpName)
		return err
	}
	if err := os.Chmod(tmpName, 0o644); err != nil {
		_ = os.Remove(tmpName)
		return err
	}
	return os.Rename(tmpName, s.path)
}

func normalizeConfig(cfg Config) (Config, error) {
	if cfg.ID == "" {
		return Config{}, fmt.Errorf("id is required")
	}
	if cfg.Name == "" {
		cfg.Name = cfg.ID
	}
	if cfg.InputURL == "" {
		return Config{}, fmt.Errorf("input_url is required")
	}
	if cfg.OutputURL == "" {
		return Config{}, fmt.Errorf("output_url is required")
	}
	if cfg.ProfileName == "" {
		cfg.ProfileName = "h264_veryfast_4m"
	}
	restart, err := normalizeRestartPolicy(cfg.Restart)
	if err != nil {
		return Config{}, err
	}
	cfg.Restart = &restart
	return cfg, nil
}

func DefaultRestartPolicy() RestartPolicy {
	return RestartPolicy{
		Enabled:        true,
		MaxAttempts:    5,
		WindowSeconds:  300,
		BackoffSeconds: 5,
	}
}

func normalizeRestartPolicy(policy *RestartPolicy) (RestartPolicy, error) {
	if policy == nil {
		return DefaultRestartPolicy(), nil
	}
	if !policy.Enabled {
		return *policy, nil
	}
	normalized := DefaultRestartPolicy()
	normalized.Enabled = true
	if policy.MaxAttempts != 0 {
		normalized.MaxAttempts = policy.MaxAttempts
	}
	if policy.WindowSeconds != 0 {
		normalized.WindowSeconds = policy.WindowSeconds
	}
	if policy.BackoffSeconds != 0 {
		normalized.BackoffSeconds = policy.BackoffSeconds
	}
	if normalized.MaxAttempts < 1 {
		return RestartPolicy{}, fmt.Errorf("restart.max_attempts must be greater than 0")
	}
	if normalized.WindowSeconds < 1 {
		return RestartPolicy{}, fmt.Errorf("restart.window_seconds must be greater than 0")
	}
	if normalized.BackoffSeconds < 1 {
		return RestartPolicy{}, fmt.Errorf("restart.backoff_seconds must be greater than 0")
	}
	return normalized, nil
}

func normalizeProfile(profile ffmpeg.Profile) (ffmpeg.Profile, error) {
	if profile.Name == "" {
		return ffmpeg.Profile{}, fmt.Errorf("name is required")
	}
	if profile.Video.Codec == "" {
		return ffmpeg.Profile{}, fmt.Errorf("video.codec is required")
	}
	if profile.Audio.Codec == "" {
		return ffmpeg.Profile{}, fmt.Errorf("audio.codec is required")
	}
	if profile.Output.Format == "" {
		profile.Output.Format = "mpegts"
	}
	return profile, nil
}

func (s *Store) ensureDefaultProfiles() {
	if _, ok := s.profiles["h264_veryfast_4m"]; !ok {
		defaultProfile := ffmpeg.H264VeryFast4M()
		s.profiles[defaultProfile.Name] = defaultProfile
	}
}

func (s *Store) sortedProfilesLocked() []ffmpeg.Profile {
	names := make([]string, 0, len(s.profiles))
	for name := range s.profiles {
		names = append(names, name)
	}
	sort.Strings(names)
	out := make([]ffmpeg.Profile, 0, len(names))
	for _, name := range names {
		out = append(out, s.profiles[name])
	}
	return out
}

package streams

import (
	"fmt"
	"sort"
	"sync"
	"time"
)

type Config struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	InputURL    string `json:"input_url"`
	OutputURL   string `json:"output_url"`
	ProfileName string `json:"profile_name"`
	VideoMap    string `json:"video_map,omitempty"`
	AudioMap    string `json:"audio_map,omitempty"`
	Enabled     bool   `json:"enabled"`
}

type State struct {
	Status       string     `json:"status"`
	PID          int        `json:"pid,omitempty"`
	StartedAt    *time.Time `json:"started_at,omitempty"`
	StoppedAt    *time.Time `json:"stopped_at,omitempty"`
	LastError    string     `json:"last_error,omitempty"`
	RestartCount int        `json:"restart_count"`
}

type View struct {
	Config Config `json:"config"`
	State  State  `json:"state"`
}

type Store struct {
	mu      sync.RWMutex
	streams map[string]Config
	states  map[string]State
}

func NewStore() *Store {
	return &Store{
		streams: make(map[string]Config),
		states:  make(map[string]State),
	}
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
	if cfg.ID == "" {
		return View{}, fmt.Errorf("id is required")
	}
	if cfg.Name == "" {
		cfg.Name = cfg.ID
	}
	if cfg.InputURL == "" {
		return View{}, fmt.Errorf("input_url is required")
	}
	if cfg.OutputURL == "" {
		return View{}, fmt.Errorf("output_url is required")
	}
	if cfg.ProfileName == "" {
		cfg.ProfileName = "h264_veryfast_4m"
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	s.streams[cfg.ID] = cfg
	if _, ok := s.states[cfg.ID]; !ok {
		s.states[cfg.ID] = State{Status: "stopped"}
	}
	return View{Config: cfg, State: s.states[cfg.ID]}, nil
}

func (s *Store) Delete(id string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.streams[id]; !ok {
		return false
	}
	delete(s.streams, id)
	delete(s.states, id)
	return true
}

func (s *Store) SetState(id string, state State) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.states[id] = state
}

func (s *Store) UpdateState(id string, update func(State) State) State {
	s.mu.Lock()
	defer s.mu.Unlock()
	next := update(s.stateLocked(id))
	s.states[id] = next
	return next
}

func (s *Store) stateLocked(id string) State {
	if state, ok := s.states[id]; ok {
		return state
	}
	return State{Status: "stopped"}
}

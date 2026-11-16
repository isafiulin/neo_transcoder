package accounts

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"

	"neotranscoder/internal/auth"
)

// ponytail: keep the existing state file and preserve retired encoder data
// as opaque JSON so updating accounts does not destroy rollback data.
type persistedState struct {
	Streams  json.RawMessage `json:"streams,omitempty"`
	Profiles json.RawMessage `json:"profiles,omitempty"`
	Users    []auth.User     `json:"users"`
	Auth     struct {
		Secret string `json:"secret"`
	} `json:"auth"`
}
type Store struct {
	mu         sync.RWMutex
	path       string
	users      map[string]auth.User
	authSecret string
	legacy     persistedState
}

func NewStore(path string) (*Store, error) {
	s := &Store{path: path, users: make(map[string]auth.User)}
	if err := s.load(); err != nil {
		return nil, err
	}
	if err := s.ensureAuth(); err != nil {
		return nil, err
	}
	return s, nil
}

func (s *Store) AuthSecret() string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.authSecret
}

func (s *Store) ListUsers() []auth.PublicUser {
	s.mu.RLock()
	defer s.mu.RUnlock()

	names := make([]string, 0, len(s.users))
	for name := range s.users {
		names = append(names, name)
	}
	sort.Strings(names)

	out := make([]auth.PublicUser, 0, len(names))
	for _, name := range names {
		out = append(out, auth.Public(s.users[name]))
	}
	return out
}

func (s *Store) GetUser(username string) (auth.User, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	user, ok := s.users[username]
	return user, ok
}

func (s *Store) Authenticate(username, password string) (auth.User, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	user, ok := s.users[username]
	if !ok || !auth.VerifyPassword(user.PasswordHash, password) {
		return auth.User{}, false
	}
	return user, true
}

func (s *Store) VerifyTokenClaims(claims auth.Claims) (auth.User, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	user, ok := s.users[claims.Subject]
	if !ok || user.TokenVersion != claims.TokenVersion {
		return auth.User{}, false
	}
	return user, true
}

func (s *Store) CreateUser(username, password string) (auth.PublicUser, error) {
	now := time.Now()
	user, err := auth.NewUser(username, password, false, now)
	if err != nil {
		return auth.PublicUser{}, err
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.users[user.Username]; ok {
		return auth.PublicUser{}, fmt.Errorf("user already exists")
	}
	s.users[user.Username] = user
	if err := s.saveLocked(); err != nil {
		delete(s.users, user.Username)
		return auth.PublicUser{}, err
	}
	return auth.Public(user), nil
}

func (s *Store) DeleteUser(username string) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.users[username]; !ok {
		return false, nil
	}
	if username == "admin" {
		return false, fmt.Errorf("default admin user cannot be deleted")
	}
	previous := s.users[username]
	delete(s.users, username)
	if err := s.saveLocked(); err != nil {
		s.users[username] = previous
		return false, err
	}
	return true, nil
}

func (s *Store) ChangePassword(username, currentPassword, newPassword string, requireCurrent bool) (auth.PublicUser, error) {
	if err := auth.ValidatePassword(newPassword); err != nil {
		return auth.PublicUser{}, err
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	user, ok := s.users[username]
	if !ok {
		return auth.PublicUser{}, fmt.Errorf("user not found")
	}
	if requireCurrent && !auth.VerifyPassword(user.PasswordHash, currentPassword) {
		return auth.PublicUser{}, fmt.Errorf("current password is invalid")
	}
	hashValue, err := auth.HashPassword(newPassword)
	if err != nil {
		return auth.PublicUser{}, err
	}
	previous := user
	user.PasswordHash = hashValue
	user.MustChangePassword = false
	user.TokenVersion++
	user.UpdatedAt = time.Now()
	s.users[username] = user
	if err := s.saveLocked(); err != nil {
		s.users[username] = previous
		return auth.PublicUser{}, err
	}
	return auth.Public(user), nil
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
		return fmt.Errorf("parse account state %s: %w", s.path, err)
	}
	s.legacy = state
	for _, user := range state.Users {
		if err := auth.ValidateUsername(user.Username); err != nil {
			return fmt.Errorf("user %q: %w", user.Username, err)
		}
		if user.PasswordHash == "" {
			return fmt.Errorf("user %q: password_hash is required", user.Username)
		}
		if user.TokenVersion < 1 {
			user.TokenVersion = 1
		}
		s.users[user.Username] = user
	}
	s.authSecret = state.Auth.Secret
	return nil
}

func (s *Store) saveLocked() error {
	if s.path == "" {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(s.path), 0o755); err != nil {
		return err
	}
	state := s.legacy
	state.Users = s.sortedUsersLocked()
	state.Auth.Secret = s.authSecret
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
	if err := os.Chmod(tmpName, 0o600); err != nil {
		_ = os.Remove(tmpName)
		return err
	}
	return os.Rename(tmpName, s.path)
}

func (s *Store) ensureAuth() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	changed := false
	if s.authSecret == "" {
		secret, err := auth.GenerateSecret()
		if err != nil {
			return err
		}
		s.authSecret = secret
		changed = true
	}
	if _, ok := s.users["admin"]; !ok {
		user, err := auth.NewUser("admin", "123456", true, time.Now())
		if err != nil {
			return err
		}
		s.users[user.Username] = user
		changed = true
	}
	if changed {
		return s.saveLocked()
	}
	return nil
}

func (s *Store) sortedUsersLocked() []auth.User {
	names := make([]string, 0, len(s.users))
	for name := range s.users {
		names = append(names, name)
	}
	sort.Strings(names)
	out := make([]auth.User, 0, len(names))
	for _, name := range names {
		out = append(out, s.users[name])
	}
	return out
}

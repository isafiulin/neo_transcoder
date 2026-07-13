package srtrelay

import (
	"bufio"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

type AuditFilter struct {
	RelayID  string
	ClientID string
	Type     string
	Limit    int
}

type AuditStore struct {
	dir           string
	retentionDays int
	mu            sync.Mutex
}

func NewAuditStore(dir string, retentionDays int) (*AuditStore, error) {
	if dir == "" {
		return nil, fmt.Errorf("audit directory is required")
	}
	if retentionDays < 1 {
		return nil, fmt.Errorf("audit retention must be greater than 0 days")
	}
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return nil, err
	}
	return &AuditStore{dir: dir, retentionDays: retentionDays}, nil
}

func (s *AuditStore) Append(event AuditEvent) (AuditEvent, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if event.Time.IsZero() {
		event.Time = time.Now().UTC()
	}
	if event.ID == "" {
		id, err := randomID()
		if err != nil {
			return AuditEvent{}, err
		}
		event.ID = id
	}
	if event.Level == "" {
		event.Level = "info"
	}
	data, err := json.Marshal(event)
	if err != nil {
		return AuditEvent{}, err
	}
	path := filepath.Join(s.dir, "srt-audit-"+event.Time.Format("2006-01-02")+".jsonl")
	file, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return AuditEvent{}, err
	}
	if _, err := file.Write(append(data, '\n')); err != nil {
		_ = file.Close()
		return AuditEvent{}, err
	}
	if err := file.Sync(); err != nil {
		_ = file.Close()
		return AuditEvent{}, err
	}
	if err := file.Close(); err != nil {
		return AuditEvent{}, err
	}
	_ = s.pruneLocked(event.Time)
	return event, nil
}

func (s *AuditStore) List(filter AuditFilter) ([]AuditEvent, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if filter.Limit < 1 || filter.Limit > 1000 {
		filter.Limit = 200
	}
	entries, err := os.ReadDir(s.dir)
	if err != nil {
		return nil, err
	}
	paths := make([]string, 0, len(entries))
	for _, entry := range entries {
		if !entry.IsDir() && strings.HasPrefix(entry.Name(), "srt-audit-") && strings.HasSuffix(entry.Name(), ".jsonl") {
			paths = append(paths, filepath.Join(s.dir, entry.Name()))
		}
	}
	sort.Sort(sort.Reverse(sort.StringSlice(paths)))

	result := make([]AuditEvent, 0, filter.Limit)
	// ponytail: daily audit files are read newest-first. This is bounded by
	// retention and limit; upgrade to an indexed store if one node reaches
	// millions of connection events per day.
	for _, path := range paths {
		remaining := filter.Limit - len(result)
		events, err := readAuditFile(path, filter, remaining)
		if err != nil {
			return nil, err
		}
		result = append(result, events...)
		if len(result) == filter.Limit {
			return result, nil
		}
	}
	return result, nil
}

func readAuditFile(path string, filter AuditFilter, limit int) ([]AuditEvent, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	// ponytail: JSONL is scanned forward and only the newest `limit` matches
	// are retained. This bounds memory; use an indexed store if scan time grows.
	ring := make([]AuditEvent, limit)
	count := 0
	start := 0
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 64*1024), 1024*1024)
	for scanner.Scan() {
		var event AuditEvent
		if json.Unmarshal(scanner.Bytes(), &event) != nil || !auditMatches(event, filter) {
			continue
		}
		if count < limit {
			ring[count] = event
			count++
			continue
		}
		ring[start] = event
		start = (start + 1) % limit
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	result := make([]AuditEvent, count)
	for index := 0; index < count; index++ {
		position := (start + count - 1 - index) % count
		result[index] = ring[position]
	}
	return result, nil
}

func auditMatches(event AuditEvent, filter AuditFilter) bool {
	return (filter.RelayID == "" || event.RelayID == filter.RelayID) &&
		(filter.ClientID == "" || event.ClientID == filter.ClientID) &&
		(filter.Type == "" || event.Type == filter.Type)
}

func (s *AuditStore) pruneLocked(now time.Time) error {
	entries, err := os.ReadDir(s.dir)
	if err != nil {
		return err
	}
	cutoff := now.AddDate(0, 0, -s.retentionDays)
	for _, entry := range entries {
		name := entry.Name()
		if entry.IsDir() || !strings.HasPrefix(name, "srt-audit-") || !strings.HasSuffix(name, ".jsonl") {
			continue
		}
		dateText := strings.TrimSuffix(strings.TrimPrefix(name, "srt-audit-"), ".jsonl")
		date, err := time.Parse("2006-01-02", dateText)
		if err == nil && date.Before(time.Date(cutoff.Year(), cutoff.Month(), cutoff.Day(), 0, 0, 0, 0, cutoff.Location())) {
			_ = os.Remove(filepath.Join(s.dir, name))
		}
	}
	return nil
}

func randomID() (string, error) {
	data := make([]byte, 12)
	if _, err := rand.Read(data); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(data), nil
}

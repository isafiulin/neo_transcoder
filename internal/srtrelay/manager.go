package srtrelay

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"os/exec"
	"sync"
	"syscall"
	"time"
)

const (
	restartWindow   = 5 * time.Minute
	restartBackoff  = 5 * time.Second
	flappingBackoff = 10 * time.Minute
	maxRestarts     = 5
	workerLineLimit = 1024 * 1024
)

type Manager struct {
	workerPath string
	store      *Store
	log        *slog.Logger

	mu       sync.Mutex
	jobs     map[string]*relayJob
	restarts map[string]restartTracker
}

type relayJob struct {
	cmd      *exec.Cmd
	stopping bool
}

type restartTracker struct {
	firstFailure time.Time
	attempts     int
}

func NewManager(workerPath string, store *Store, log *slog.Logger) *Manager {
	return &Manager{
		workerPath: workerPath,
		store:      store,
		log:        log,
		jobs:       make(map[string]*relayJob),
		restarts:   make(map[string]restartTracker),
	}
}

func (m *Manager) Start(id string) error {
	return m.start(id, false)
}

func (m *Manager) start(id string, restarted bool) error {
	view, ok := m.store.GetRelay(id)
	if !ok {
		return fmt.Errorf("SRT relay not found")
	}
	if !view.Config.Enabled {
		return fmt.Errorf("SRT relay is disabled")
	}
	path, err := exec.LookPath(m.workerPath)
	if err != nil {
		return fmt.Errorf("SRT worker: %w", err)
	}
	config := WorkerConfig{Relay: view.Config}
	if view.Config.Direction == DirectionPublish {
		config.PublishPassphrase = m.store.PublishPassphrase(id)
	} else {
		config.Clients = m.store.WorkerClients(id)
	}
	data, err := json.Marshal(config)
	if err != nil {
		return err
	}

	m.mu.Lock()
	if _, exists := m.jobs[id]; exists {
		m.mu.Unlock()
		return fmt.Errorf("SRT relay is already running")
	}
	cmd := exec.Command(path, "--config-stdin")
	setWorkerProcessAttrs(cmd)
	cmd.Stdin = bytes.NewReader(append(data, '\n'))
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		m.mu.Unlock()
		return err
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		m.mu.Unlock()
		return err
	}
	if err := cmd.Start(); err != nil {
		m.mu.Unlock()
		return err
	}
	job := &relayJob{cmd: cmd}
	m.jobs[id] = job
	if !restarted {
		delete(m.restarts, id)
	}
	m.mu.Unlock()

	m.store.UpdateState(id, func(state RelayState) RelayState {
		state.Status = "starting"
		state.PID = cmd.Process.Pid
		state.LastError = ""
		state.Flapping = false
		if restarted {
			state.RestartCount++
		}
		return state
	})
	m.log.Info("SRT relay worker started", "relay_id", id, "pid", cmd.Process.Pid)
	go m.readEvents(id, stdout)
	go m.readStderr(id, stderr)
	go m.wait(id, job)
	return nil
}

func (m *Manager) IsRunning(id string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	_, ok := m.jobs[id]
	return ok
}

func (m *Manager) StartEnabled() {
	for _, view := range m.store.ListRelays() {
		if !view.Config.Enabled {
			continue
		}
		if err := m.Start(view.Config.ID); err != nil {
			m.log.Error("start enabled SRT relay", "relay_id", view.Config.ID, "error", err)
			m.store.UpdateState(view.Config.ID, func(state RelayState) RelayState {
				state.Status = "error"
				state.LastError = err.Error()
				return state
			})
		}
	}
}

func (m *Manager) Stop(id string) error {
	m.mu.Lock()
	job, ok := m.jobs[id]
	if !ok {
		m.mu.Unlock()
		if _, exists := m.store.GetRelay(id); !exists {
			return fmt.Errorf("SRT relay not found")
		}
		return nil
	}
	job.stopping = true
	delete(m.restarts, id)
	process := job.cmd.Process
	m.mu.Unlock()

	m.store.UpdateState(id, func(state RelayState) RelayState {
		state.Status = "stopping"
		return state
	})
	if err := process.Signal(syscall.SIGTERM); err != nil {
		_ = process.Kill()
	}
	go func() {
		timer := time.NewTimer(5 * time.Second)
		defer timer.Stop()
		<-timer.C
		m.mu.Lock()
		current := m.jobs[id]
		m.mu.Unlock()
		if current == job {
			_ = process.Kill()
		}
	}()
	return nil
}

func (m *Manager) Restart(id string) error {
	if err := m.Stop(id); err != nil {
		return err
	}
	deadline := time.Now().Add(6 * time.Second)
	for time.Now().Before(deadline) {
		m.mu.Lock()
		_, running := m.jobs[id]
		m.mu.Unlock()
		if !running {
			return m.Start(id)
		}
		time.Sleep(50 * time.Millisecond)
	}
	return fmt.Errorf("SRT relay did not stop in time")
}

func (m *Manager) StopAll() {
	m.mu.Lock()
	ids := make([]string, 0, len(m.jobs))
	for id := range m.jobs {
		ids = append(ids, id)
	}
	m.mu.Unlock()
	for _, id := range ids {
		_ = m.Stop(id)
	}
}

func (m *Manager) readEvents(id string, reader io.Reader) {
	scanner := bufio.NewScanner(reader)
	scanner.Buffer(make([]byte, 64*1024), workerLineLimit)
	for scanner.Scan() {
		var event WorkerEvent
		if err := json.Unmarshal(scanner.Bytes(), &event); err != nil {
			m.log.Warn("invalid SRT worker event", "relay_id", id, "error", err)
			continue
		}
		m.store.ApplyWorkerEvent(id, event)
	}
	if err := scanner.Err(); err != nil {
		m.log.Warn("SRT worker event pipe failed", "relay_id", id, "error", err)
	}
}

func (m *Manager) readStderr(id string, reader io.Reader) {
	scanner := bufio.NewScanner(reader)
	scanner.Buffer(make([]byte, 64*1024), workerLineLimit)
	for scanner.Scan() {
		m.log.Warn("SRT worker", "relay_id", id, "message", scanner.Text())
	}
}

func (m *Manager) wait(id string, job *relayJob) {
	err := job.cmd.Wait()
	m.mu.Lock()
	if m.jobs[id] != job {
		m.mu.Unlock()
		return
	}
	delete(m.jobs, id)
	stopping := job.stopping
	m.mu.Unlock()

	if stopping {
		m.store.CloseRelaySessions(id, "SRT worker stopped", time.Now().UTC())
		m.store.UpdateState(id, func(state RelayState) RelayState {
			state.Status = "stopped"
			state.PID = 0
			state.ActiveClients = 0
			return state
		})
		return
	}
	reason := "SRT worker exited"
	if err != nil {
		reason = err.Error()
	}
	m.store.CloseRelaySessions(id, reason, time.Now().UTC())
	m.store.UpdateState(id, func(state RelayState) RelayState {
		state.Status = "error"
		state.PID = 0
		state.ActiveClients = 0
		state.LastError = reason
		return state
	})
	_, _ = m.store.RecordAudit(AuditEvent{Type: "relay_worker_exited", Level: "error", RelayID: id, Reason: reason})

	view, exists := m.store.GetRelay(id)
	if !exists || !view.Config.Enabled {
		return
	}
	if !m.allowRestart(id, time.Now()) {
		m.store.UpdateState(id, func(state RelayState) RelayState {
			state.Status = "flapping"
			state.Flapping = true
			state.LastError = "SRT worker exceeded restart limit"
			return state
		})
		time.AfterFunc(flappingBackoff, func() { m.retryFlapping(id) })
		return
	}
	m.store.UpdateState(id, func(state RelayState) RelayState {
		state.Status = "restarting"
		return state
	})
	time.AfterFunc(restartBackoff, func() {
		if err := m.start(id, true); err != nil {
			m.log.Error("SRT relay restart failed", "relay_id", id, "error", err)
		}
	})
}

func (m *Manager) retryFlapping(id string) {
	view, exists := m.store.GetRelay(id)
	if !exists || !view.Config.Enabled || view.State.Status != "flapping" {
		return
	}
	m.mu.Lock()
	delete(m.restarts, id)
	_, running := m.jobs[id]
	m.mu.Unlock()
	if running {
		return
	}
	m.store.UpdateState(id, func(state RelayState) RelayState {
		state.Status = "restarting"
		state.Flapping = false
		return state
	})
	if err := m.start(id, true); err != nil {
		m.log.Error("SRT relay flapping retry failed", "relay_id", id, "error", err)
		m.store.UpdateState(id, func(state RelayState) RelayState {
			state.Status = "flapping"
			state.Flapping = true
			state.LastError = err.Error()
			return state
		})
		time.AfterFunc(flappingBackoff, func() { m.retryFlapping(id) })
	}
}

func (m *Manager) allowRestart(id string, now time.Time) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	tracker := m.restarts[id]
	if tracker.firstFailure.IsZero() || now.Sub(tracker.firstFailure) > restartWindow {
		tracker = restartTracker{firstFailure: now}
	}
	tracker.attempts++
	m.restarts[id] = tracker
	return tracker.attempts <= maxRestarts
}

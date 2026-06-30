package streams

import (
	"context"
	"fmt"
	"log/slog"
	"os/exec"
	"sync"
	"time"

	"neotranscoder/internal/ffmpeg"
)

type JobManager struct {
	ffmpegPath string
	store      *Store
	log        *slog.Logger

	mu   sync.Mutex
	jobs map[string]*job
}

type job struct {
	cancel   context.CancelFunc
	cmd      *exec.Cmd
	stopping bool
	done     chan struct{}
}

func NewJobManager(ffmpegPath string, store *Store, log *slog.Logger) *JobManager {
	return &JobManager{
		ffmpegPath: ffmpegPath,
		store:      store,
		log:        log,
		jobs:       make(map[string]*job),
	}
}

func (m *JobManager) Start(id string) error {
	view, ok := m.store.Get(id)
	if !ok {
		return fmt.Errorf("stream not found")
	}

	args, err := ffmpeg.BuildArgs(ffmpeg.Stream{
		InputURL:  view.Config.InputURL,
		OutputURL: view.Config.OutputURL,
		VideoMap:  view.Config.VideoMap,
		AudioMap:  view.Config.AudioMap,
	}, profileByName(view.Config.ProfileName))
	if err != nil {
		return err
	}

	m.mu.Lock()
	if _, exists := m.jobs[id]; exists {
		m.mu.Unlock()
		return fmt.Errorf("stream already running")
	}

	ctx, cancel := context.WithCancel(context.Background())
	cmd := exec.CommandContext(ctx, m.ffmpegPath, args...)
	if err := cmd.Start(); err != nil {
		cancel()
		m.mu.Unlock()
		m.store.UpdateState(id, func(state State) State {
			state.Status = "error"
			state.LastError = err.Error()
			return state
		})
		return err
	}

	m.jobs[id] = &job{cancel: cancel, cmd: cmd, done: make(chan struct{})}
	m.mu.Unlock()

	started := time.Now()
	m.store.SetState(id, State{
		Status:    "running",
		PID:       cmd.Process.Pid,
		StartedAt: &started,
	})
	m.log.Info("stream started", "id", id, "pid", cmd.Process.Pid)

	go m.wait(id, cmd)
	return nil
}

func (m *JobManager) Stop(id string) error {
	m.mu.Lock()
	running, ok := m.jobs[id]
	if ok {
		running.stopping = true
	}
	m.mu.Unlock()
	if !ok {
		return fmt.Errorf("stream not running")
	}

	running.cancel()
	stopping := time.Now()
	m.store.UpdateState(id, func(state State) State {
		state.Status = "stopping"
		state.StoppedAt = &stopping
		return state
	})

	select {
	case <-running.done:
	case <-time.After(5 * time.Second):
		return fmt.Errorf("timeout waiting for stream to stop")
	}

	m.log.Info("stream stopped", "id", id)
	return nil
}

func (m *JobManager) StopAll() {
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

func (m *JobManager) wait(id string, cmd *exec.Cmd) {
	err := cmd.Wait()

	m.mu.Lock()
	current := m.jobs[id]
	if current != nil && current.cmd == cmd {
		delete(m.jobs, id)
	}
	m.mu.Unlock()
	if current != nil {
		close(current.done)
	}

	stopped := time.Now()
	m.store.UpdateState(id, func(state State) State {
		state.PID = 0
		state.StoppedAt = &stopped
		if current != nil && current.stopping {
			state.Status = "stopped"
			state.LastError = ""
		} else if err != nil {
			state.Status = "error"
			state.LastError = err.Error()
		} else {
			state.Status = "stopped"
			state.LastError = ""
		}
		return state
	})
	if err != nil {
		m.log.Warn("stream exited", "id", id, "error", err)
	}
}

func profileByName(name string) ffmpeg.Profile {
	// ponytail: v0 ships one profile; upgrade path is persisted profile CRUD.
	return ffmpeg.H264VeryFast4M()
}

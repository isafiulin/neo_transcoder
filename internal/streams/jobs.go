package streams

import (
	"bufio"
	"bytes"
	"context"
	"fmt"
	"io"
	"log/slog"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"time"

	"neotranscoder/internal/ffmpeg"
)

type JobManager struct {
	ffmpegPath string
	sys        ffmpeg.SystemConfig
	store      *Store
	log        *slog.Logger

	mu       sync.Mutex
	jobs     map[string]*job
	restarts map[string]restartTracker
}

type job struct {
	cancel   context.CancelFunc
	cmd      *exec.Cmd
	stopping bool
	done     chan struct{}
}

type restartTracker struct {
	firstFailure time.Time
	attempts     int
}

func NewJobManager(ffmpegPath string, sys ffmpeg.SystemConfig, store *Store, log *slog.Logger) *JobManager {
	return &JobManager{
		ffmpegPath: ffmpegPath,
		sys:        sys,
		store:      store,
		log:        log,
		jobs:       make(map[string]*job),
		restarts:   make(map[string]restartTracker),
	}
}

func (m *JobManager) Start(id string) error {
	return m.start(id, false)
}

func (m *JobManager) start(id string, restarted bool) error {
	view, ok := m.store.Get(id)
	if !ok {
		return fmt.Errorf("stream not found")
	}

	profile, ok := m.store.GetProfile(view.Config.ProfileName)
	if !ok {
		return fmt.Errorf("profile %q not found", view.Config.ProfileName)
	}

	args, err := ffmpeg.BuildArgs(ffmpeg.Stream{
		InputURL:     view.Config.InputURL,
		OutputURL:    view.Config.OutputURL,
		SourceType:   view.Config.SourceType,
		VideoMap:     view.Config.VideoMap,
		AudioMap:     view.Config.AudioMap,
		AudioMaps:    view.Config.AudioMaps,
		DisableAudio: view.Config.DisableAudio,
		Logo: ffmpeg.LogoOverlay{
			Enabled: view.Config.Logo.Enabled,
			Path:    view.Config.Logo.Path,
			X:       view.Config.Logo.X,
			Y:       view.Config.Logo.Y,
		},
		Options:   view.Config.Options,
		KeepStats: view.Config.KeepStats,
	}, profile, m.sys.WithLogLevel(view.Config.LogLevel))
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
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		cancel()
		m.mu.Unlock()
		return err
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		cancel()
		m.mu.Unlock()
		return err
	}
	if err := cmd.Start(); err != nil {
		cancel()
		m.mu.Unlock()
		m.store.UpdateState(id, func(state State) State {
			state.Status = "error"
			state.ErrorCode = classifyError(err.Error())
			state.LastError = err.Error()
			return state
		})
		return err
	}

	runningJob := &job{cancel: cancel, cmd: cmd, done: make(chan struct{})}
	m.jobs[id] = runningJob
	if !restarted {
		delete(m.restarts, id)
	}
	m.mu.Unlock()

	started := time.Now()
	m.store.UpdateState(id, func(state State) State {
		state.Status = "running"
		state.PID = cmd.Process.Pid
		state.StartedAt = &started
		state.StoppedAt = nil
		state.LastError = ""
		state.ErrorCode = ""
		state.Flapping = false
		state.Metrics = nil
		state.Process = nil
		if restarted {
			state.RestartCount++
		}
		return state
	})
	m.log.Info("stream started", "id", id, "pid", cmd.Process.Pid)

	go m.captureProgress(id, stdout, cancel)
	go m.captureStderr(id, stderr, cancel)
	go m.monitorProcess(id, cmd.Process.Pid, view.Config.Watchdog, cancel, runningJob.done)
	go m.wait(id, cmd)
	return nil
}

// maxLogLineBytes bounds how much a single stderr/progress token can grow
// before we give up on it. bufio.Scanner's default cap (64KB) is generous
// headroom for legitimately long lines (filter graph dumps, long URLs) while
// still bounded; scanCRLF (below) keeps ffmpeg's console stats line - a bare
// \r rewrite with no trailing \n, enabled per-stream via Config.KeepStats -
// from ever approaching this cap in the first place.
const maxLogLineBytes = 1 << 20

// scanCRLF is bufio.ScanLines plus treating a bare \r as a token boundary
// too, not just \n. Without this, ffmpeg's console stats line (a single
// \r-rewritten line with no trailing \n) is invisible to the scanner as a
// line boundary and grows without bound for as long as the stream runs,
// eventually hitting maxLogLineBytes, erroring the scanner out, and forcing
// a stream restart. With it, each \r-update is its own short token instead.
func scanCRLF(data []byte, atEOF bool) (advance int, token []byte, err error) {
	if atEOF && len(data) == 0 {
		return 0, nil, nil
	}
	if i := bytes.IndexAny(data, "\r\n"); i >= 0 {
		advance = i + 1
		if data[i] == '\r' && i+1 < len(data) && data[i+1] == '\n' {
			advance++
		}
		return advance, data[:i], nil
	}
	if atEOF {
		return len(data), data, nil
	}
	return 0, nil, nil
}

func (m *JobManager) Stop(id string) error {
	m.mu.Lock()
	running, ok := m.jobs[id]
	if ok {
		running.stopping = true
		delete(m.restarts, id)
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
	manualStop := current != nil && current.stopping
	next := m.store.UpdateState(id, func(state State) State {
		state.PID = 0
		state.StoppedAt = &stopped
		if manualStop {
			state.Status = "stopped"
			state.ErrorCode = ""
			state.LastError = ""
			state.Process = nil
		} else if err != nil {
			state.Status = "error"
			if state.ErrorCode == "" {
				state.ErrorCode = ErrorProcessExit
			}
			if state.LastError == "" {
				state.LastError = err.Error()
			}
			state.Process = nil
		} else {
			state.Status = "stopped"
			state.ErrorCode = ""
			state.LastError = ""
			state.Process = nil
		}
		return state
	})
	if err != nil {
		m.log.Warn("stream exited", "id", id, "error", err)
	}
	if err != nil && !manualStop {
		m.maybeRestart(id, next.LastError)
	}
}

func (m *JobManager) captureStderr(id string, stderr io.Reader, kill context.CancelFunc) {
	scanner := bufio.NewScanner(stderr)
	scanner.Split(scanCRLF)
	scanner.Buffer(make([]byte, 0, 64*1024), maxLogLineBytes)
	for scanner.Scan() {
		line := scanner.Text()
		if isFFmpegStatsLine(line) {
			continue
		}
		level, message := parseFFmpegLevel(line)
		code := ""
		if isPacketLossNoise(strings.ToLower(message)) {
			// Occasional corrupt/lost UDP packets are expected on multicast
			// IPTV input; never treat them as an operator-facing error or
			// let them override to "error" below, regardless of what
			// severity ffmpeg itself tagged the line with.
			level = "warn"
			code = ErrorPacketLoss
		} else {
			if level == "warn" || level == "error" {
				code = classifyError(message)
			}
			if code != "" && code != ErrorUnknown {
				level = "error"
				m.store.UpdateState(id, func(state State) State {
					state.ErrorCode = code
					state.LastError = message
					return state
				})
			}
		}
		m.store.AppendLogCode(id, level, code, message)
	}
	if err := scanner.Err(); err != nil {
		m.store.AppendLogCode(id, "warn", classifyError(err.Error()), err.Error())
		// The pipe is no longer being drained, so ffmpeg will block on its
		// next stderr write and hang instead of exiting. Kill it so wait()
		// observes a real exit and the normal restart/backoff path applies,
		// rather than leaving the stream stuck reporting "running" forever.
		kill()
	}
}

func (m *JobManager) maybeRestart(id, reason string) {
	view, ok := m.store.Get(id)
	if !ok || !view.Config.Enabled || view.Config.Restart == nil || !view.Config.Restart.Enabled {
		return
	}

	policy := *view.Config.Restart
	now := time.Now()

	m.mu.Lock()
	tracker := m.restarts[id]
	if tracker.firstFailure.IsZero() || now.Sub(tracker.firstFailure) > time.Duration(policy.WindowSeconds)*time.Second {
		tracker = restartTracker{firstFailure: now}
	}
	tracker.attempts++
	m.restarts[id] = tracker
	attempts := tracker.attempts
	m.mu.Unlock()

	if attempts > policy.MaxAttempts {
		m.store.UpdateState(id, func(state State) State {
			state.Status = "flapping"
			state.Flapping = true
			state.ErrorCode = ErrorProcessExit
			state.LastError = reason
			return state
		})
		m.store.AppendLogCode(id, "error", ErrorProcessExit, "restart limit reached; stream marked as flapping")
		return
	}

	backoff := time.Duration(policy.BackoffSeconds) * time.Second
	m.store.UpdateState(id, func(state State) State {
		state.Status = "restarting"
		state.ErrorCode = ErrorProcessExit
		state.LastError = reason
		return state
	})

	go func() {
		time.Sleep(backoff)
		view, ok := m.store.Get(id)
		if !ok || !view.Config.Enabled {
			return
		}
		if err := m.start(id, true); err != nil {
			m.store.AppendLogCode(id, "error", classifyError(err.Error()), fmt.Sprintf("restart failed: %v", err))
			m.maybeRestart(id, err.Error())
		}
	}()
}

func (m *JobManager) monitorProcess(id string, pid int, policy *WatchdogPolicy, kill context.CancelFunc, done <-chan struct{}) {
	if policy == nil {
		defaultPolicy := DefaultWatchdogPolicy()
		policy = &defaultPolicy
	}
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()

	var previous procSample
	var previousAt time.Time
	var memoryExceededSince time.Time
	startedAt := time.Now()
	for {
		select {
		case <-done:
			return
		case now := <-ticker.C:
			current, err := readProcSample(pid)
			if err != nil {
				return
			}

			process := Process{
				MemoryBytes: current.rssBytes,
				UpdatedAt:   now,
			}
			if !previousAt.IsZero() {
				elapsed := now.Sub(previousAt).Seconds()
				if elapsed > 0 {
					// ponytail: Linux USER_HZ is assumed to be 100; upgrade path is sysconf via x/sys/unix if kernels need it.
					process.CPUPercent = float64(current.cpuTicks-previous.cpuTicks) / linuxClockTicksPerSecond / elapsed * 100
				}
			}

			m.store.UpdateState(id, func(state State) State {
				state.Process = &process
				return state
			})
			view, ok := m.store.Get(id)
			if ok {
				action := watchdogAction(*policy, view.State, process.MemoryBytes, startedAt, memoryExceededSince, now)
				memoryExceededSince = action.memoryExceededSince
				if action.reason != "" {
					m.store.UpdateState(id, func(state State) State {
						state.Status = "error"
						state.ErrorCode = ErrorWatchdog
						state.LastError = action.reason
						return state
					})
					m.store.AppendLogCode(id, "error", ErrorWatchdog, action.reason)
					kill()
					return
				}
			}
			previous = current
			previousAt = now
		}
	}
}

type watchdogDecision struct {
	reason              string
	memoryExceededSince time.Time
}

func watchdogAction(policy WatchdogPolicy, state State, memoryBytes int64, startedAt, memoryExceededSince, now time.Time) watchdogDecision {
	if !policy.Enabled {
		return watchdogDecision{memoryExceededSince: memoryExceededSince}
	}
	lastProgress := startedAt
	if state.Metrics != nil && !state.Metrics.UpdatedAt.IsZero() {
		lastProgress = state.Metrics.UpdatedAt
	}
	if now.Sub(lastProgress) > time.Duration(policy.ProgressTimeoutSeconds)*time.Second {
		return watchdogDecision{
			reason:              fmt.Sprintf("watchdog: no ffmpeg progress for %s", now.Sub(lastProgress).Round(time.Second)),
			memoryExceededSince: memoryExceededSince,
		}
	}
	if policy.MaxMemoryBytes <= 0 || memoryBytes <= policy.MaxMemoryBytes {
		return watchdogDecision{}
	}
	if memoryExceededSince.IsZero() {
		return watchdogDecision{memoryExceededSince: now}
	}
	if now.Sub(memoryExceededSince) >= time.Duration(policy.MemoryGraceSeconds)*time.Second {
		return watchdogDecision{
			reason: fmt.Sprintf(
				"watchdog: memory usage %d bytes exceeded limit %d bytes for %s",
				memoryBytes,
				policy.MaxMemoryBytes,
				now.Sub(memoryExceededSince).Round(time.Second),
			),
			memoryExceededSince: memoryExceededSince,
		}
	}
	return watchdogDecision{memoryExceededSince: memoryExceededSince}
}

func (m *JobManager) captureProgress(id string, stdout io.Reader, kill context.CancelFunc) {
	scanner := bufio.NewScanner(stdout)
	scanner.Split(scanCRLF)
	scanner.Buffer(make([]byte, 0, 64*1024), maxLogLineBytes)
	fields := make(map[string]string)
	for scanner.Scan() {
		line := scanner.Text()
		key, value, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		fields[key] = value
		if key == "progress" {
			metrics := parseProgress(fields)
			m.store.UpdateState(id, func(state State) State {
				state.Metrics = &metrics
				return state
			})
			fields = make(map[string]string)
		}
	}
	if err := scanner.Err(); err != nil {
		m.store.AppendLogCode(id, "warn", classifyError(err.Error()), err.Error())
		// Same reasoning as captureStderr: an undrained pipe hangs ffmpeg, so
		// force the exit instead of leaving a zombie "running" stream.
		kill()
	}
}

func parseProgress(fields map[string]string) Metrics {
	return Metrics{
		Frame:     parseInt(fields["frame"]),
		FPS:       parseFloat(fields["fps"]),
		Bitrate:   fields["bitrate"],
		TotalSize: parseInt(fields["total_size"]),
		OutTime:   fields["out_time"],
		OutTimeMS: parseInt(fields["out_time_ms"]),
		Speed:     fields["speed"],
		Progress:  fields["progress"],
		UpdatedAt: time.Now(),
	}
}

func parseInt(value string) int64 {
	if value == "" || value == "N/A" {
		return 0
	}
	parsed, err := strconv.ParseInt(value, 10, 64)
	if err != nil {
		return 0
	}
	return parsed
}

func parseFloat(value string) float64 {
	if value == "" || value == "N/A" {
		return 0
	}
	parsed, err := strconv.ParseFloat(value, 64)
	if err != nil {
		return 0
	}
	return parsed
}

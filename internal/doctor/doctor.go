package doctor

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"neotranscoder/internal/config"
)

type Check struct {
	Name   string `json:"name"`
	OK     bool   `json:"ok"`
	Detail string `json:"detail"`
}

func Run(cfg config.Config) []Check {
	checks := []Check{
		fileExecutable("ffmpeg", cfg.FFmpeg.Path),
		fileExecutable("ffprobe", cfg.FFmpeg.FFprobePath),
		executableRuns("srt_worker", cfg.SRT.WorkerPath, "version"),
		dirWritable("storage_dir", filepath.Dir(cfg.Storage.Path)),
		dirWritable("log_dir", filepath.Dir(cfg.Logs.Path)),
		dirWritable("srt_state_dir", filepath.Dir(cfg.SRT.StatePath)),
		dirWritable("srt_audit_dir", cfg.SRT.AuditDir),
	}
	return checks
}

func executableRuns(name, path string, args ...string) Check {
	base := fileExecutable(name, path)
	if !base.OK {
		return base
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	output, err := exec.CommandContext(ctx, path, args...).CombinedOutput()
	if err != nil {
		return Check{Name: name, OK: false, Detail: fmt.Sprintf("%s: %v: %s", path, err, output)}
	}
	return Check{Name: name, OK: true, Detail: fmt.Sprintf("%s runnable", path)}
}

func HasFailure(checks []Check) bool {
	for _, check := range checks {
		if !check.OK {
			return true
		}
	}
	return false
}

func fileExecutable(name, path string) Check {
	if path == "" {
		return Check{Name: name, OK: false, Detail: "path is empty"}
	}
	if _, err := exec.LookPath(path); err != nil {
		return Check{Name: name, OK: false, Detail: err.Error()}
	}
	return Check{Name: name, OK: true, Detail: path}
}

func dirWritable(name, path string) Check {
	if path == "" {
		return Check{Name: name, OK: false, Detail: "path is empty"}
	}
	if err := os.MkdirAll(path, 0o755); err != nil {
		return Check{Name: name, OK: false, Detail: err.Error()}
	}
	probe := filepath.Join(path, ".neotranscoder-write-check")
	if err := os.WriteFile(probe, []byte("ok\n"), 0o644); err != nil {
		return Check{Name: name, OK: false, Detail: err.Error()}
	}
	_ = os.Remove(probe)
	return Check{Name: name, OK: true, Detail: fmt.Sprintf("%s writable", path)}
}

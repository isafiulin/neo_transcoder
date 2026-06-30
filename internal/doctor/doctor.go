package doctor

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

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
		dirWritable("storage_dir", filepath.Dir(cfg.Storage.Path)),
		dirWritable("log_dir", filepath.Dir(cfg.Logs.Path)),
	}
	return checks
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

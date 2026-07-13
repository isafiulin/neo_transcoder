package doctor

import (
	"os"
	"path/filepath"
	"testing"

	"neotranscoder/internal/config"
)

func TestDoctorReportsRunnableToolsAndWritableDirectories(t *testing.T) {
	dir := t.TempDir()
	executable := filepath.Join(dir, "tool")
	if err := os.WriteFile(executable, []byte("#!/bin/sh\nexit 0\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	cfg := config.Default()
	cfg.FFmpeg.Path = executable
	cfg.FFmpeg.FFprobePath = executable
	cfg.SRT.WorkerPath = executable
	cfg.Storage.Path = filepath.Join(dir, "state", "state.json")
	cfg.Logs.Path = filepath.Join(dir, "logs", "app.log")
	cfg.SRT.StatePath = filepath.Join(dir, "srt-state", "state.json")
	cfg.SRT.AuditDir = filepath.Join(dir, "audit")
	checks := Run(cfg)
	if len(checks) != 7 || HasFailure(checks) {
		t.Fatalf("doctor checks = %+v", checks)
	}
}

func TestDoctorReportsMissingFailingAndUnwritableRequirements(t *testing.T) {
	dir := t.TempDir()
	failing := filepath.Join(dir, "failing-worker")
	if err := os.WriteFile(failing, []byte("#!/bin/sh\necho broken >&2\nexit 7\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	fileInsteadOfDir := filepath.Join(dir, "not-a-directory")
	if err := os.WriteFile(fileInsteadOfDir, []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	if check := executableRuns("worker", failing, "version"); check.OK || check.Detail == "" {
		t.Fatalf("failing executable check = %+v", check)
	}
	if check := fileExecutable("missing", filepath.Join(dir, "missing")); check.OK {
		t.Fatalf("missing executable check = %+v", check)
	}
	if check := dirWritable("state", filepath.Join(fileInsteadOfDir, "child")); check.OK {
		t.Fatalf("unwritable directory check = %+v", check)
	}
	if !HasFailure([]Check{{Name: "ok", OK: true}, {Name: "bad", OK: false}}) {
		t.Fatal("failed doctor result was not detected")
	}
}

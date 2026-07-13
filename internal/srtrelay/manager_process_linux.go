//go:build linux

package srtrelay

import (
	"os/exec"
	"syscall"
)

func setWorkerProcessAttrs(cmd *exec.Cmd) {
	// Keep a worker from surviving an abrupt manager crash outside systemd.
	cmd.SysProcAttr = &syscall.SysProcAttr{Pdeathsig: syscall.SIGTERM}
}

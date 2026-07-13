//go:build !linux

package srtrelay

import "os/exec"

func setWorkerProcessAttrs(_ *exec.Cmd) {}

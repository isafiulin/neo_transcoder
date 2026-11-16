//go:build !libsrt || !cgo

package srtworker

import (
	"fmt"
	"time"
)

func nativeStartup() error {
	return fmt.Errorf("SRT worker was built without libsrt support")
}

func nativeCleanup() {}

func nativeOpenListener(string, int, int, int, int, bool, uintptr) (int, error) {
	return -1, fmt.Errorf("SRT worker was built without libsrt support")
}

func nativeOpenCaller(string, int, int, int, string, string) (int, error) {
	return -1, fmt.Errorf("SRT worker was built without libsrt support")
}

func nativeAccept(int) (int, string, int, string, string, bool, error) {
	return -1, "", 0, "", "", false, fmt.Errorf("SRT worker was built without libsrt support")
}

func nativeSendBatch(int, []byte, int, []byte) (int, error) {
	return 0, fmt.Errorf("SRT worker was built without libsrt support")
}

func nativeStats(int) (nativeStatistics, error) {
	return nativeStatistics{}, fmt.Errorf("SRT worker was built without libsrt support")
}

func nativeClose(int) {}

func nativePause(d time.Duration) { time.Sleep(d) }

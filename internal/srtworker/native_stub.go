//go:build !libsrt || !cgo

package srtworker

import "fmt"

func nativeStartup() error {
	return fmt.Errorf("SRT worker was built without libsrt support")
}

func nativeCleanup() {}

func nativeOpenListener(string, int, int, int, int, uintptr) (int, error) {
	return -1, fmt.Errorf("SRT worker was built without libsrt support")
}

func nativeOpenCaller(string, int, int, int, string, string) (int, error) {
	return -1, fmt.Errorf("SRT worker was built without libsrt support")
}

func nativeAccept(int) (int, string, int, string, string, bool, error) {
	return -1, "", 0, "", "", false, fmt.Errorf("SRT worker was built without libsrt support")
}

func nativeSend(int, []byte) error {
	return fmt.Errorf("SRT worker was built without libsrt support")
}

func nativeStats(int) (nativeStatistics, error) {
	return nativeStatistics{}, fmt.Errorf("SRT worker was built without libsrt support")
}

func nativeClose(int) {}

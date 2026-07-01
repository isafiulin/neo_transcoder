//go:build !linux

package sysinfo

const platformSupported = false

func readCPUTicks() (total, idle uint64, ok bool) {
	return 0, 0, false
}

func readLoadAvg() (load1, load5, load15 float64, ok bool) {
	return 0, 0, 0, false
}

func readMemory() (used, total uint64, ok bool) {
	return 0, 0, false
}

func readUptime() (int64, bool) {
	return 0, false
}

func readDisk(path string) (used, total uint64, ok bool) {
	return 0, 0, false
}

package streams

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

const linuxClockTicksPerSecond = 100

type procSample struct {
	cpuTicks int64
	rssBytes int64
}

func readProcSample(pid int) (procSample, error) {
	statData, err := os.ReadFile(fmt.Sprintf("/proc/%d/stat", pid))
	if err != nil {
		return procSample{}, err
	}
	return parseProcStat(string(statData), int64(os.Getpagesize()))
}

func parseProcStat(stat string, pageSize int64) (procSample, error) {
	end := strings.LastIndex(stat, ")")
	if end < 0 || end+2 >= len(stat) {
		return procSample{}, fmt.Errorf("invalid proc stat")
	}

	fields := strings.Fields(stat[end+2:])
	if len(fields) < 22 {
		return procSample{}, fmt.Errorf("short proc stat")
	}

	utime, err := strconv.ParseInt(fields[11], 10, 64)
	if err != nil {
		return procSample{}, err
	}
	stime, err := strconv.ParseInt(fields[12], 10, 64)
	if err != nil {
		return procSample{}, err
	}
	rssPages, err := strconv.ParseInt(fields[21], 10, 64)
	if err != nil {
		return procSample{}, err
	}

	return procSample{
		cpuTicks: utime + stime,
		rssBytes: rssPages * pageSize,
	}, nil
}

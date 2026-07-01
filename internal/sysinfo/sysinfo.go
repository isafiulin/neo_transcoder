package sysinfo

import (
	"context"
	"runtime"
	"sync"
	"time"
)

type Snapshot struct {
	CPUPercent          float64 `json:"cpu_percent"`
	LoadAvg1            float64 `json:"load_avg_1"`
	LoadAvg5            float64 `json:"load_avg_5"`
	LoadAvg15           float64 `json:"load_avg_15"`
	MemoryUsedBytes     uint64  `json:"memory_used_bytes"`
	MemoryTotalBytes    uint64  `json:"memory_total_bytes"`
	DiskUsedBytes       uint64  `json:"disk_used_bytes"`
	DiskTotalBytes      uint64  `json:"disk_total_bytes"`
	SystemUptimeSeconds int64   `json:"system_uptime_seconds"`
	AppUptimeSeconds    int64   `json:"app_uptime_seconds"`
	CPUCores            int     `json:"cpu_cores"`
	Supported           bool    `json:"supported"`
}

type Collector struct {
	mu        sync.RWMutex
	startedAt time.Time
	diskPath  string
	latest    Snapshot
	prevTotal uint64
	prevIdle  uint64
	havePrev  bool
}

func NewCollector(diskPath string) *Collector {
	if diskPath == "" {
		diskPath = "/"
	}
	return &Collector{startedAt: time.Now(), diskPath: diskPath}
}

func (c *Collector) Run(ctx context.Context) {
	c.sample()
	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			c.sample()
		}
	}
}

func (c *Collector) Snapshot() Snapshot {
	c.mu.RLock()
	snap := c.latest
	c.mu.RUnlock()
	snap.AppUptimeSeconds = int64(time.Since(c.startedAt).Seconds())
	snap.CPUCores = runtime.NumCPU()
	return snap
}

func (c *Collector) sample() {
	total, idle, cpuOK := readCPUTicks()
	load1, load5, load15, loadOK := readLoadAvg()
	memUsed, memTotal, memOK := readMemory()
	diskUsed, diskTotal, diskOK := readDisk(c.diskPath)
	uptime, uptimeOK := readUptime()

	c.mu.Lock()
	defer c.mu.Unlock()

	var cpuPercent float64
	if cpuOK && c.havePrev && total > c.prevTotal {
		totalDelta := total - c.prevTotal
		idleDelta := idle - c.prevIdle
		if totalDelta > 0 {
			cpuPercent = 100 * (1 - float64(idleDelta)/float64(totalDelta))
		}
	}
	if cpuOK {
		c.prevTotal, c.prevIdle = total, idle
		c.havePrev = true
	}

	snap := Snapshot{Supported: platformSupported}
	if cpuOK {
		snap.CPUPercent = cpuPercent
	}
	if loadOK {
		snap.LoadAvg1, snap.LoadAvg5, snap.LoadAvg15 = load1, load5, load15
	}
	if memOK {
		snap.MemoryUsedBytes, snap.MemoryTotalBytes = memUsed, memTotal
	}
	if diskOK {
		snap.DiskUsedBytes, snap.DiskTotalBytes = diskUsed, diskTotal
	}
	if uptimeOK {
		snap.SystemUptimeSeconds = uptime
	}
	c.latest = snap
}

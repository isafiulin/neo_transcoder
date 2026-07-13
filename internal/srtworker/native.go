package srtworker

type nativeStatistics struct {
	BytesSent      int64
	PacketsSent    int64
	PacketsLost    int64
	PacketsRetrans int64
	PacketsDropped int64
	BitrateBPS     int64
	RTTMS          float64
}

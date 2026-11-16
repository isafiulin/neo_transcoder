//go:build !linux

package srtworker

import "net"

func restrictMulticastToJoinedGroups(*net.UDPConn) error { return nil }

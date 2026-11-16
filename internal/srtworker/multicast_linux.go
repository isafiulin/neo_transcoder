package srtworker

import (
	"net"
	"syscall"
)

const ipMulticastAll = 0x31 // IP_MULTICAST_ALL, linux/in.h

// Go binds multicast listeners to 0.0.0.0:port, and Linux defaults
// IP_MULTICAST_ALL to 1: such a socket receives every group joined by any
// process on that port. With many relays on one port each worker would read
// and forward all of the host's multicast traffic.
func restrictMulticastToJoinedGroups(connection *net.UDPConn) error {
	raw, err := connection.SyscallConn()
	if err != nil {
		return err
	}
	var optionErr error
	if err := raw.Control(func(fd uintptr) {
		optionErr = syscall.SetsockoptInt(int(fd), syscall.IPPROTO_IP, ipMulticastAll, 0)
	}); err != nil {
		return err
	}
	return optionErr
}

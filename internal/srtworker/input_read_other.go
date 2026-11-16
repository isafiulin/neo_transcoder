//go:build unix && !(linux && (amd64 || arm64))

package srtworker

import "syscall"

type datagramReader struct {
	buffer []byte
}

func newDatagramReader() *datagramReader {
	return &datagramReader{buffer: make([]byte, 65535)}
}

// drain reads the datagrams already queued on the socket without waiting.
func (r *datagramReader) drain(fd int, limit int, handle func([]byte)) error {
	for total := 0; total < limit; {
		count, _, err := syscall.Recvfrom(fd, r.buffer, syscall.MSG_DONTWAIT)
		switch err {
		case nil:
		case syscall.EINTR:
			continue
		case syscall.EAGAIN:
			return nil
		default:
			return err
		}
		handle(r.buffer[:count])
		total++
	}
	return nil
}

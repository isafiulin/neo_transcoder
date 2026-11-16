//go:build linux && (amd64 || arm64)

package srtworker

import (
	"syscall"
	"unsafe"
)

const (
	readBatchSize   = 16
	maxDatagramSize = 65535
)

type mmsghdr struct {
	header syscall.Msghdr
	length uint32
	_      [4]byte
}

// datagramReader receives up to readBatchSize datagrams per recvmmsg call.
type datagramReader struct {
	buffers []byte
	iovecs  [readBatchSize]syscall.Iovec
	headers [readBatchSize]mmsghdr
}

func newDatagramReader() *datagramReader {
	reader := &datagramReader{buffers: make([]byte, readBatchSize*maxDatagramSize)}
	for index := range reader.headers {
		reader.iovecs[index].Base = &reader.buffers[index*maxDatagramSize]
		reader.iovecs[index].SetLen(maxDatagramSize)
		reader.headers[index].header.Iov = &reader.iovecs[index]
		reader.headers[index].header.Iovlen = 1
	}
	return reader
}

// drain reads the datagrams already queued on the socket without waiting.
func (r *datagramReader) drain(fd int, limit int, handle func([]byte)) error {
	for total := 0; total < limit; {
		count, _, errno := syscall.Syscall6(sysRecvmmsg, uintptr(fd),
			uintptr(unsafe.Pointer(&r.headers[0])), readBatchSize, syscall.MSG_DONTWAIT, 0, 0)
		switch errno {
		case 0:
		case syscall.EINTR:
			continue
		case syscall.EAGAIN:
			return nil
		default:
			return errno
		}
		for index := 0; index < int(count); index++ {
			offset := index * maxDatagramSize
			handle(r.buffers[offset : offset+int(r.headers[index].length)])
		}
		total += int(count)
		if int(count) < readBatchSize {
			return nil
		}
	}
	return nil
}

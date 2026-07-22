//go:build libsrt && cgo

package srtworker

/*
#cgo pkg-config: srt
#include <stdlib.h>
#include "bridge.h"
*/
import "C"

import (
	"fmt"
	"unsafe"
)

//export goSRTAuthorize
func goSRTAuthorize(handle C.uintptr_t, _socket C.int, _handshakeVersion C.int, remoteIP *C.char, remotePort C.int, streamID *C.char, passphrase *C.char, passphraseCapacity C.int) C.int {
	value, ok := workerRegistry.Load(uintptr(handle))
	if !ok {
		return 503
	}
	w := value.(*worker)
	secret, decision := w.authorize(C.GoString(remoteIP), int(remotePort), C.GoString(streamID))
	if decision != 0 {
		return C.int(decision)
	}
	capacity := int(passphraseCapacity)
	if len(secret)+1 > capacity {
		return 500
	}
	target := unsafe.Slice((*byte)(unsafe.Pointer(passphrase)), capacity)
	copy(target, secret)
	target[len(secret)] = 0
	return 0
}

func nativeStartup() error {
	errorBuffer := make([]byte, 512)
	if C.neo_srt_startup((*C.char)(unsafe.Pointer(&errorBuffer[0])), C.int(len(errorBuffer))) != 0 {
		return nativeError(errorBuffer)
	}
	return nil
}

func nativeCleanup() {
	C.neo_srt_cleanup()
}

func nativeOpenListener(bindAddress string, port, latencyMS, payloadSize, minimumVersion int, enforceEncryption bool, handle uintptr) (int, error) {
	address := C.CString(bindAddress)
	defer C.free(unsafe.Pointer(address))
	enforced := C.int(0)
	if enforceEncryption {
		enforced = 1
	}
	errorBuffer := make([]byte, 512)
	socket := C.neo_srt_listener_open(
		address,
		C.int(port),
		C.int(latencyMS),
		C.int(payloadSize),
		C.int(minimumVersion),
		enforced,
		C.uintptr_t(handle),
		(*C.char)(unsafe.Pointer(&errorBuffer[0])),
		C.int(len(errorBuffer)),
	)
	if socket < 0 {
		return -1, nativeError(errorBuffer)
	}
	return int(socket), nil
}

func nativeOpenCaller(destinationAddress string, port, latencyMS, payloadSize int, streamID, passphrase string) (int, error) {
	address := C.CString(destinationAddress)
	stream := C.CString(streamID)
	secret := C.CString(passphrase)
	defer C.free(unsafe.Pointer(address))
	defer C.free(unsafe.Pointer(stream))
	defer C.free(unsafe.Pointer(secret))
	errorBuffer := make([]byte, 512)
	socket := C.neo_srt_caller_open(
		address, C.int(port), C.int(latencyMS), C.int(payloadSize), stream, secret,
		(*C.char)(unsafe.Pointer(&errorBuffer[0])), C.int(len(errorBuffer)),
	)
	if socket < 0 {
		return -1, nativeError(errorBuffer)
	}
	return int(socket), nil
}

func nativeAccept(listener int) (int, string, int, string, string, bool, error) {
	remoteIP := make([]byte, 128)
	streamID := make([]byte, 513)
	peerVersion := make([]byte, 32)
	errorBuffer := make([]byte, 512)
	var remotePort C.int
	var encrypted C.int
	socket := C.neo_srt_accept(
		C.int(listener),
		(*C.char)(unsafe.Pointer(&remoteIP[0])), C.int(len(remoteIP)),
		&remotePort,
		(*C.char)(unsafe.Pointer(&streamID[0])), C.int(len(streamID)),
		(*C.char)(unsafe.Pointer(&peerVersion[0])), C.int(len(peerVersion)),
		&encrypted,
		(*C.char)(unsafe.Pointer(&errorBuffer[0])), C.int(len(errorBuffer)),
	)
	if socket < 0 {
		return -1, "", 0, "", "", false, nativeError(errorBuffer)
	}
	return int(socket), cString(remoteIP), int(remotePort), cString(streamID), cString(peerVersion), encrypted != 0, nil
}

func nativeSend(socket int, data []byte) error {
	if len(data) == 0 {
		return nil
	}
	errorBuffer := make([]byte, 512)
	if C.neo_srt_send(
		C.int(socket),
		(*C.char)(unsafe.Pointer(&data[0])),
		C.int(len(data)),
		(*C.char)(unsafe.Pointer(&errorBuffer[0])),
		C.int(len(errorBuffer)),
	) != 0 {
		return nativeError(errorBuffer)
	}
	return nil
}

func nativeStats(socket int) (nativeStatistics, error) {
	var stats C.NeoSRTStats
	errorBuffer := make([]byte, 512)
	if C.neo_srt_stats(C.int(socket), &stats, (*C.char)(unsafe.Pointer(&errorBuffer[0])), C.int(len(errorBuffer))) != 0 {
		return nativeStatistics{}, nativeError(errorBuffer)
	}
	return nativeStatistics{
		BytesSent:      int64(stats.bytes_sent),
		PacketsSent:    int64(stats.packets_sent),
		PacketsLost:    int64(stats.packets_lost),
		PacketsRetrans: int64(stats.packets_retrans),
		PacketsDropped: int64(stats.packets_dropped),
		BitrateBPS:     int64(stats.bitrate_bps),
		RTTMS:          float64(stats.rtt_ms),
	}, nil
}

func nativeClose(socket int) {
	C.neo_srt_close(C.int(socket))
}

func nativeError(buffer []byte) error {
	message := cString(buffer)
	if message == "" {
		message = "unknown SRT error"
	}
	return fmt.Errorf("%s", message)
}

func cString(buffer []byte) string {
	for index, value := range buffer {
		if value == 0 {
			return string(buffer[:index])
		}
	}
	return string(buffer)
}

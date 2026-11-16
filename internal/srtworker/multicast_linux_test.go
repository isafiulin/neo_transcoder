package srtworker

import (
	"fmt"
	"net"
	"testing"
	"time"

	"neotranscoder/internal/srtrelay"
)

func TestMulticastInputIgnoresOtherGroupsOnSamePort(t *testing.T) {
	probe, err := net.ListenUDP("udp4", &net.UDPAddr{})
	if err != nil {
		t.Fatal(err)
	}
	port := probe.LocalAddr().(*net.UDPAddr).Port
	probe.Close()

	groupA := net.IPv4(239, 255, 77, 1)
	inputA, err := openMulticast(srtrelay.Relay{InputURL: fmt.Sprintf("udp://%s:%d", groupA, port)})
	if err != nil {
		t.Skipf("multicast unavailable: %v", err)
	}
	defer inputA.Close()
	inputB, err := openMulticast(srtrelay.Relay{InputURL: fmt.Sprintf("udp://239.255.77.2:%d", port)})
	if err != nil {
		t.Skipf("multicast unavailable: %v", err)
	}
	defer inputB.Close()

	sender, err := net.DialUDP("udp4", nil, &net.UDPAddr{IP: groupA, Port: port})
	if err != nil {
		t.Skipf("multicast send unavailable: %v", err)
	}
	defer sender.Close()
	if _, err := sender.Write([]byte("group-a")); err != nil {
		t.Skipf("multicast send unavailable: %v", err)
	}

	buffer := make([]byte, 64)
	_ = inputA.SetReadDeadline(time.Now().Add(time.Second))
	if _, _, err := inputA.ReadFromUDPAddrPort(buffer); err != nil {
		t.Skipf("multicast loopback unavailable: %v", err)
	}
	_ = inputB.SetReadDeadline(time.Now().Add(300 * time.Millisecond))
	if count, _, err := inputB.ReadFromUDPAddrPort(buffer); err == nil {
		t.Fatalf("input for another group received %q", buffer[:count])
	}
}

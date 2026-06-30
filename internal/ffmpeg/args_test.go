package ffmpeg

import (
	"reflect"
	"testing"
)

func TestBuildArgsH264(t *testing.T) {
	got, err := BuildArgs(Stream{
		InputURL:  "udp://239.1.1.1:1234?localaddr=10.0.0.5",
		OutputURL: "udp://239.2.2.2:1234?pkt_size=1316",
	}, H264VeryFast4M())
	if err != nil {
		t.Fatal(err)
	}
	want := []string{
		"-hide_banner",
		"-nostdin",
		"-i", "udp://239.1.1.1:1234?localaddr=10.0.0.5",
		"-map", "0:v:0",
		"-map", "0:a:0?",
		"-c:v", "libx264",
		"-preset", "veryfast",
		"-tune", "zerolatency",
		"-b:v", "4000k",
		"-maxrate", "4000k",
		"-bufsize", "8000k",
		"-c:a", "aac",
		"-b:a", "128k",
		"-f", "mpegts",
		"udp://239.2.2.2:1234?pkt_size=1316",
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("args mismatch\ngot:  %#v\nwant: %#v", got, want)
	}
}

func TestBuildArgsRejectsHTTPInput(t *testing.T) {
	_, err := BuildArgs(Stream{
		InputURL:  "http://example.com/live",
		OutputURL: "udp://239.2.2.2:1234",
	}, H264VeryFast4M())
	if err == nil {
		t.Fatal("expected URL validation error")
	}
}

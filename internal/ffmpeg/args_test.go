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
		"-progress", "pipe:1",
		"-stats_period", "1",
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

func TestBuildArgsTemplateProfile(t *testing.T) {
	got, err := BuildArgs(Stream{
		InputURL:  "udp://239.1.1.1:1234",
		OutputURL: "udp://239.2.2.2:1234",
		Options: map[string]string{
			"video_bitrate": "6M",
		},
	}, Profile{
		Name: "template",
		Template: TemplateProfile{
			Args: []string{
				"-hide_banner",
				"-i", "${i}?overrun_nonfatal=1",
				"-b:v", "${video_bitrate}",
				"${o}?pkt_size=1316",
			},
			Defaults: map[string]string{
				"video_bitrate": "4M",
			},
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	want := []string{
		"-progress", "pipe:1",
		"-stats_period", "1",
		"-hide_banner",
		"-i", "udp://239.1.1.1:1234?overrun_nonfatal=1",
		"-b:v", "6M",
		"udp://239.2.2.2:1234?pkt_size=1316",
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("args mismatch\ngot:  %#v\nwant: %#v", got, want)
	}
}

func TestBuildArgsTemplateRejectsUnknownVariable(t *testing.T) {
	_, err := BuildArgs(Stream{
		InputURL:  "udp://239.1.1.1:1234",
		OutputURL: "udp://239.2.2.2:1234",
	}, Profile{
		Name: "template",
		Template: TemplateProfile{
			Args: []string{"-b:v", "${missing}"},
		},
	})
	if err == nil {
		t.Fatal("expected unknown variable error")
	}
}

func TestBuildArgsFileLogoAndNoAudio(t *testing.T) {
	got, err := BuildArgs(Stream{
		InputURL:     "/srv/media/test.ts",
		OutputURL:    "udp://239.2.2.2:1234",
		SourceType:   "file",
		DisableAudio: true,
		Logo: LogoOverlay{
			Enabled: true,
			Path:    "/srv/media/logo.png",
			X:       12,
			Y:       20,
		},
	}, H264VeryFast4M())
	if err != nil {
		t.Fatal(err)
	}
	wantContains := []string{
		"-re",
		"-i", "/srv/media/test.ts",
		"-i", "/srv/media/logo.png",
		"-filter_complex", "[0:v:0][1:v:0]overlay=12:20[v]",
		"-map", "[v]",
	}
	for _, want := range wantContains {
		if !contains(got, want) {
			t.Fatalf("expected args to contain %q: %#v", want, got)
		}
	}
	if contains(got, "-c:a") {
		t.Fatalf("audio codec should be omitted when audio is disabled: %#v", got)
	}
}

func contains(values []string, want string) bool {
	for _, value := range values {
		if value == want {
			return true
		}
	}
	return false
}

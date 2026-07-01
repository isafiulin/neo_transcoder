package ffmpeg

import (
	"reflect"
	"testing"
)

// defaultSystemConfig mirrors config.Default().FFmpeg so these tests exercise
// the same values a real deployment would use. Note there's no Threads or
// DiscardCorrupt here anymore - those are opt-in per profile now (see
// AdvancedProfile), not a system default.
func defaultSystemConfig() SystemConfig {
	return SystemConfig{
		UDPFifoSize:        100000000,
		UDPBufferSize:      8388608,
		UDPOverrunNonfatal: true,
		UDPReuse:           true,
		PktSize:            1316,
		AnalyzeDuration:    10000000,
		ProbeSize:          20000000,
		LogLevel:           "warning",
	}
}

func intPtr(v int) *int {
	return &v
}

// TestBuildArgsH264 pins the default command shape to what it was before
// -fflags/-err_detect/-g/-keyint_min/-sc_threshold/-threads were briefly
// on by default: they changed encoder behavior (GOP structure, corrupt-input
// tolerance) and shifted output bitrate, which nobody asked for. Only the
// UDP-transport and probing additions (safe by construction) remain.
func TestBuildArgsH264(t *testing.T) {
	got, err := BuildArgs(Stream{
		InputURL:  "udp://239.1.1.1:1234?localaddr=10.0.0.5",
		OutputURL: "udp://239.2.2.2:1234?pkt_size=1316",
	}, H264VeryFast4M(), defaultSystemConfig())
	if err != nil {
		t.Fatal(err)
	}
	want := []string{
		"-hide_banner",
		"-nostdin",
		"-nostats",
		"-loglevel", "level+warning",
		"-progress", "pipe:1",
		"-stats_period", "1",
		"-analyzeduration", "10000000",
		"-probesize", "20000000",
		"-i", "udp://239.1.1.1:1234?buffer_size=8388608&fifo_size=100000000&localaddr=10.0.0.5&overrun_nonfatal=1&reuse=1",
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
	}, H264VeryFast4M(), defaultSystemConfig())
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
	}, defaultSystemConfig())
	if err != nil {
		t.Fatal(err)
	}
	want := []string{
		"-nostats",
		"-loglevel", "level+info",
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
	}, defaultSystemConfig())
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
	}, H264VeryFast4M(), defaultSystemConfig())
	if err != nil {
		t.Fatal(err)
	}
	wantContains := []string{
		"-re",
		"-i", "/srv/media/test.ts",
		"-i", "/srv/media/logo.png",
		"-filter_complex", "[0:v:0][1:v:0]overlay=12:20[v]",
		"-map", "[v]",
		// pkt_size is added to the output URL automatically since it wasn't
		// already present.
		"udp://239.2.2.2:1234?pkt_size=1316",
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

func TestBuildArgsFPSScale(t *testing.T) {
	profile := H264VeryFast4M()
	profile.Video.FPS = "25"
	profile.Video.Scale = "1280x720"

	got, err := BuildArgs(Stream{
		InputURL:  "udp://239.1.1.1:1234",
		OutputURL: "udp://239.2.2.2:1234",
	}, profile, defaultSystemConfig())
	if err != nil {
		t.Fatal(err)
	}
	wantContains := []string{
		"-r", "25",
		"-vf", "scale=1280x720",
	}
	for _, want := range wantContains {
		if !contains(got, want) {
			t.Fatalf("expected args to contain %q: %#v", want, got)
		}
	}
}

func TestBuildArgsLogoWithScale(t *testing.T) {
	profile := H264VeryFast4M()
	profile.Video.Scale = "1280x720"

	got, err := BuildArgs(Stream{
		InputURL:  "udp://239.1.1.1:1234",
		OutputURL: "udp://239.2.2.2:1234",
		Logo: LogoOverlay{
			Enabled: true,
			Path:    "/srv/media/logo.png",
			X:       12,
			Y:       20,
		},
	}, profile, defaultSystemConfig())
	if err != nil {
		t.Fatal(err)
	}
	if !contains(got, "[0:v:0]scale=1280x720[scaled];[scaled][1:v:0]overlay=12:20[v]") {
		t.Fatalf("expected scale to be folded into the logo filter_complex: %#v", got)
	}
	if contains(got, "-vf") {
		t.Fatalf("-vf must not be used alongside -filter_complex: %#v", got)
	}
}

func TestBuildArgsExtraArgs(t *testing.T) {
	profile := H264VeryFast4M()
	profile.ExtraArgs = []string{"-flush_packets", "1"}

	got, err := BuildArgs(Stream{
		InputURL:  "udp://239.1.1.1:1234",
		OutputURL: "udp://239.2.2.2:1234",
	}, profile, defaultSystemConfig())
	if err != nil {
		t.Fatal(err)
	}
	if !contains(got, "-flush_packets") {
		t.Fatalf("expected extra_args to be present: %#v", got)
	}
	// extra_args must land before the trailing "-f <format> <output>".
	if got[len(got)-5] != "-flush_packets" {
		t.Fatalf("expected extra_args right before -f/output, got: %#v", got)
	}
}

// TestBuildArgsDefaultsExcludeAdvancedFlags is the regression test for the
// bitrate/stability bug: none of these encode-affecting flags should ever
// appear unless the profile's Advanced section explicitly asks for them.
func TestBuildArgsDefaultsExcludeAdvancedFlags(t *testing.T) {
	got, err := BuildArgs(Stream{
		InputURL:  "udp://239.1.1.1:1234",
		OutputURL: "udp://239.2.2.2:1234",
	}, H264VeryFast4M(), defaultSystemConfig())
	if err != nil {
		t.Fatal(err)
	}
	forbidden := []string{
		"-fflags", "-err_detect", "-g", "-keyint_min",
		"-sc_threshold", "-threads", "-minrate", "-x264-params",
	}
	for _, flag := range forbidden {
		if contains(got, flag) {
			t.Fatalf("expected %q to be absent by default: %#v", flag, got)
		}
	}
}

func TestBuildArgsKeepStats(t *testing.T) {
	got, err := BuildArgs(Stream{
		InputURL:  "udp://239.1.1.1:1234",
		OutputURL: "udp://239.2.2.2:1234",
		KeepStats: true,
	}, H264VeryFast4M(), defaultSystemConfig())
	if err != nil {
		t.Fatal(err)
	}
	if contains(got, "-nostats") {
		t.Fatalf("expected -nostats to be omitted when KeepStats is true: %#v", got)
	}
}

func TestBuildArgsDefaultIncludesNostats(t *testing.T) {
	got, err := BuildArgs(Stream{
		InputURL:  "udp://239.1.1.1:1234",
		OutputURL: "udp://239.2.2.2:1234",
	}, H264VeryFast4M(), defaultSystemConfig())
	if err != nil {
		t.Fatal(err)
	}
	if !contains(got, "-nostats") {
		t.Fatalf("expected -nostats to be present by default: %#v", got)
	}
}

func TestBuildArgsAdvancedFlags(t *testing.T) {
	profile := H264VeryFast4M()
	profile.Advanced = AdvancedProfile{
		EnableGenpts:       true,
		DiscardCorrupt:     true,
		IgnoreDecodeErrors: true,
		VideoThreads:       intPtr(2),
		GOP:                intPtr(50),
		KeyintMin:          intPtr(50),
		SCThreshold:        intPtr(0),
		Minrate:            "2000k",
		X264Params:         "nal-hrd=cbr",
	}

	got, err := BuildArgs(Stream{
		InputURL:  "udp://239.1.1.1:1234",
		OutputURL: "udp://239.2.2.2:1234",
	}, profile, defaultSystemConfig())
	if err != nil {
		t.Fatal(err)
	}
	wantContains := []string{
		"-fflags", "+genpts+discardcorrupt",
		"-err_detect", "ignore_err",
		"-threads", "2",
		"-g", "50",
		"-keyint_min", "50",
		"-sc_threshold", "0",
		"-minrate", "2000k",
		"-x264-params", "nal-hrd=cbr",
	}
	for _, want := range wantContains {
		if !contains(got, want) {
			t.Fatalf("expected args to contain %q: %#v", want, got)
		}
	}
}

func TestAugmentMulticastInputURLPreservesExistingParams(t *testing.T) {
	out, err := augmentMulticastInputURL("udp://239.1.1.1:1234?localaddr=10.0.0.5", "multicast", defaultSystemConfig())
	if err != nil {
		t.Fatal(err)
	}
	want := "udp://239.1.1.1:1234?buffer_size=8388608&fifo_size=100000000&localaddr=10.0.0.5&overrun_nonfatal=1&reuse=1"
	if out != want {
		t.Fatalf("augmentMulticastInputURL() = %q, want %q", out, want)
	}
}

func TestAugmentMulticastInputURLSkipsFileAndRTP(t *testing.T) {
	sys := defaultSystemConfig()
	if out, err := augmentMulticastInputURL("/srv/media/test.ts", "file", sys); err != nil || out != "/srv/media/test.ts" {
		t.Fatalf("file source should be left untouched, got %q, err %v", out, err)
	}
	if out, err := augmentMulticastInputURL("rtp://239.1.1.1:1234", "multicast", sys); err != nil || out != "rtp://239.1.1.1:1234" {
		t.Fatalf("rtp scheme should be left untouched, got %q, err %v", out, err)
	}
}

func TestAugmentUDPOutputURLRespectsExistingPktSize(t *testing.T) {
	out, err := augmentUDPOutputURL("udp://239.2.2.2:1234?pkt_size=1400", "mpegts", defaultSystemConfig())
	if err != nil {
		t.Fatal(err)
	}
	if out != "udp://239.2.2.2:1234?pkt_size=1400" {
		t.Fatalf("expected existing pkt_size to be preserved, got %q", out)
	}
}

func TestSystemConfigWithLogLevel(t *testing.T) {
	sys := defaultSystemConfig()
	if sys.LogLevel != "warning" {
		t.Fatalf("precondition: default LogLevel = %q, want warning", sys.LogLevel)
	}
	overridden := sys.WithLogLevel("info")
	if overridden.LogLevel != "info" {
		t.Fatalf("WithLogLevel(%q) = %q, want info", "info", overridden.LogLevel)
	}
	unchanged := sys.WithLogLevel("")
	if unchanged.LogLevel != "warning" {
		t.Fatalf("WithLogLevel(\"\") = %q, want warning (unchanged)", unchanged.LogLevel)
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

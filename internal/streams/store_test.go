package streams

import (
	"path/filepath"
	"testing"

	"neotranscoder/internal/ffmpeg"
)

func TestStorePersistsStreams(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state.json")
	store, err := NewStore(path)
	if err != nil {
		t.Fatal(err)
	}

	if _, err := store.Upsert(Config{
		ID:        "channel_1",
		InputURL:  "udp://239.1.1.1:1234",
		OutputURL: "udp://239.2.2.2:1234",
	}); err != nil {
		t.Fatal(err)
	}

	loaded, err := NewStore(path)
	if err != nil {
		t.Fatal(err)
	}
	view, ok := loaded.Get("channel_1")
	if !ok {
		t.Fatal("stream was not loaded")
	}
	if view.Config.ProfileName != "h264_veryfast_4m" {
		t.Fatalf("profile = %q", view.Config.ProfileName)
	}
	if view.Config.Restart == nil || !view.Config.Restart.Enabled || view.Config.Restart.MaxAttempts != 5 {
		t.Fatalf("restart policy = %+v", view.Config.Restart)
	}
	if view.State.Status != "stopped" {
		t.Fatalf("status = %q", view.State.Status)
	}
}

func TestStorePersistsProfiles(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state.json")
	store, err := NewStore(path)
	if err != nil {
		t.Fatal(err)
	}

	profile, err := store.UpsertProfile(testProfile("h264_fast_6m"))
	if err != nil {
		t.Fatal(err)
	}

	loaded, err := NewStore(path)
	if err != nil {
		t.Fatal(err)
	}
	got, ok := loaded.GetProfile(profile.Name)
	if !ok {
		t.Fatal("profile was not loaded")
	}
	if got.Video.Bitrate != "6000k" {
		t.Fatalf("bitrate = %q", got.Video.Bitrate)
	}
}

func TestStreamLogLevelOverride(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state.json")
	store, err := NewStore(path)
	if err != nil {
		t.Fatal(err)
	}

	view, err := store.Upsert(Config{
		ID:        "channel_1",
		InputURL:  "udp://239.1.1.1:1234",
		OutputURL: "udp://239.2.2.2:1234",
		LogLevel:  "info",
	})
	if err != nil {
		t.Fatal(err)
	}
	if view.Config.LogLevel != "info" {
		t.Fatalf("log_level = %q, want info", view.Config.LogLevel)
	}

	if _, err := store.Upsert(Config{
		ID:        "channel_2",
		InputURL:  "udp://239.1.1.1:1234",
		OutputURL: "udp://239.2.2.2:1234",
		LogLevel:  "verbose",
	}); err == nil {
		t.Fatal("expected invalid log_level to be rejected")
	}
}

func testProfile(name string) ffmpeg.Profile {
	return ffmpeg.Profile{
		Name: name,
		Video: ffmpeg.VideoProfile{
			Codec:   "libx264",
			Preset:  "fast",
			Bitrate: "6000k",
			Maxrate: "6000k",
			Bufsize: "12000k",
		},
		Audio: ffmpeg.AudioProfile{
			Codec:   "aac",
			Bitrate: "128k",
		},
		Output: ffmpeg.OutputProfile{
			Format: "mpegts",
		},
	}
}

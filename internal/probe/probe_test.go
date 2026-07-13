package probe

import (
	"context"
	"os"
	"path/filepath"
	"testing"
)

func TestParseFFprobeJSON(t *testing.T) {
	got, err := Parse([]byte(`{
	  "streams": [
	    {"index":0,"codec_name":"h264","codec_type":"video","width":1920,"height":1080,"avg_frame_rate":"25/1"},
	    {
	      "index":1,
	      "codec_name":"aac",
	      "codec_type":"audio",
	      "bit_rate":"128000",
	      "channels":2,
	      "channel_layout":"stereo",
	      "tags":{"language":"eng"}
	    }
	  ],
	  "format": {"format_name":"mpegts","bit_rate":"4128000"}
	}`))
	if err != nil {
		t.Fatal(err)
	}
	if len(got.Streams) != 2 {
		t.Fatalf("streams = %d, want 2", len(got.Streams))
	}
	if got.Streams[0].CodecName != "h264" || got.Streams[1].CodecType != "audio" {
		t.Fatalf("unexpected streams: %+v", got.Streams)
	}
	if got.Streams[1].Channels != 2 || got.Streams[1].Tags["language"] != "eng" {
		t.Fatalf("unexpected audio metadata: %+v", got.Streams[1])
	}
}

func TestRunExecutesFFprobeAndParsesOutput(t *testing.T) {
	path := writeProbeScript(t, `printf '%s' '{"streams":[{"index":0,"codec_type":"video","codec_name":"h264"}],"format":{"format_name":"mpegts"}}'`)
	result, err := Run(context.Background(), path, "udp://239.1.1.1:1234")
	if err != nil {
		t.Fatal(err)
	}
	if result.Format.FormatName != "mpegts" || len(result.Streams) != 1 {
		t.Fatalf("probe result = %+v", result)
	}
}

func TestRunReportsProcessAndMalformedJSONFailures(t *testing.T) {
	failing := writeProbeScript(t, "exit 7")
	if _, err := Run(context.Background(), failing, "udp://239.1.1.1:1234"); err == nil {
		t.Fatal("expected ffprobe process error")
	}
	malformed := writeProbeScript(t, "printf 'not-json'")
	if _, err := Run(context.Background(), malformed, "udp://239.1.1.1:1234"); err == nil {
		t.Fatal("expected malformed ffprobe JSON error")
	}
	cancelled, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := Run(cancelled, malformed, "udp://239.1.1.1:1234"); err == nil {
		t.Fatal("expected cancelled probe error")
	}
}

func writeProbeScript(t *testing.T, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "ffprobe")
	if err := os.WriteFile(path, []byte("#!/bin/sh\nset -eu\n"+body+"\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	return path
}

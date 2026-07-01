package probe

import "testing"

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

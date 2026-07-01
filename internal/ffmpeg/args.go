package ffmpeg

import (
	"fmt"
	"net/url"
)

type Stream struct {
	InputURL  string
	OutputURL string
	VideoMap  string
	AudioMap  string
}

type Profile struct {
	Name   string        `json:"name"`
	Video  VideoProfile  `json:"video"`
	Audio  AudioProfile  `json:"audio"`
	Output OutputProfile `json:"output"`
}

type VideoProfile struct {
	Codec   string `json:"codec"`
	Preset  string `json:"preset,omitempty"`
	Bitrate string `json:"bitrate,omitempty"`
	Maxrate string `json:"maxrate,omitempty"`
	Bufsize string `json:"bufsize,omitempty"`
	Tune    string `json:"tune,omitempty"`
}

type AudioProfile struct {
	Codec   string `json:"codec"`
	Bitrate string `json:"bitrate,omitempty"`
}

type OutputProfile struct {
	Format string `json:"format"`
}

func H264VeryFast4M() Profile {
	return Profile{
		Name: "h264_veryfast_4m",
		Video: VideoProfile{
			Codec:   "libx264",
			Preset:  "veryfast",
			Bitrate: "4000k",
			Maxrate: "4000k",
			Bufsize: "8000k",
			Tune:    "zerolatency",
		},
		Audio: AudioProfile{
			Codec:   "aac",
			Bitrate: "128k",
		},
		Output: OutputProfile{
			Format: "mpegts",
		},
	}
}

func BuildArgs(stream Stream, profile Profile) ([]string, error) {
	if err := validateURL(stream.InputURL); err != nil {
		return nil, fmt.Errorf("input url: %w", err)
	}
	if err := validateURL(stream.OutputURL); err != nil {
		return nil, fmt.Errorf("output url: %w", err)
	}
	if profile.Video.Codec == "" {
		return nil, fmt.Errorf("video codec is required")
	}
	if profile.Audio.Codec == "" {
		return nil, fmt.Errorf("audio codec is required")
	}
	format := profile.Output.Format
	if format == "" {
		format = "mpegts"
	}

	videoMap := stream.VideoMap
	if videoMap == "" {
		videoMap = "0:v:0"
	}
	audioMap := stream.AudioMap
	if audioMap == "" {
		audioMap = "0:a:0?"
	}

	args := []string{
		"-hide_banner",
		"-nostdin",
		"-progress", "pipe:1",
		"-stats_period", "1",
		"-i", stream.InputURL,
		"-map", videoMap,
		"-map", audioMap,
		"-c:v", profile.Video.Codec,
	}

	if profile.Video.Preset != "" {
		args = append(args, "-preset", profile.Video.Preset)
	}
	if profile.Video.Tune != "" {
		args = append(args, "-tune", profile.Video.Tune)
	}
	if profile.Video.Bitrate != "" {
		args = append(args, "-b:v", profile.Video.Bitrate)
	}
	if profile.Video.Maxrate != "" {
		args = append(args, "-maxrate", profile.Video.Maxrate)
	}
	if profile.Video.Bufsize != "" {
		args = append(args, "-bufsize", profile.Video.Bufsize)
	}

	args = append(args, "-c:a", profile.Audio.Codec)
	if profile.Audio.Bitrate != "" && profile.Audio.Codec != "copy" {
		args = append(args, "-b:a", profile.Audio.Bitrate)
	}
	args = append(args, "-f", format, stream.OutputURL)
	return args, nil
}

func validateURL(raw string) error {
	if raw == "" {
		return fmt.Errorf("is required")
	}
	u, err := url.Parse(raw)
	if err != nil {
		return err
	}
	// ponytail: v0 only accepts network URLs; upgrade path is explicit file/srt/rtmp schemes per product need.
	if u.Scheme != "udp" && u.Scheme != "rtp" {
		return fmt.Errorf("scheme must be udp or rtp")
	}
	if u.Host == "" {
		return fmt.Errorf("host is required")
	}
	return nil
}

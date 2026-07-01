package ffmpeg

import (
	"fmt"
	"net/url"
	"regexp"
)

type Stream struct {
	InputURL     string
	OutputURL    string
	SourceType   string
	VideoMap     string
	AudioMap     string
	AudioMaps    []string
	DisableAudio bool
	Logo         LogoOverlay
	Options      map[string]string
}

type LogoOverlay struct {
	Enabled bool
	Path    string
	X       int
	Y       int
}

type Profile struct {
	Name     string          `json:"name"`
	Video    VideoProfile    `json:"video"`
	Audio    AudioProfile    `json:"audio"`
	Output   OutputProfile   `json:"output"`
	Template TemplateProfile `json:"template,omitempty"`
}

type TemplateProfile struct {
	Args     []string          `json:"args,omitempty"`
	Defaults map[string]string `json:"defaults,omitempty"`
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

func H264UltrafastTemplate4M() Profile {
	return Profile{
		Name: "h264_ultrafast_template_4m",
		Template: TemplateProfile{
			Args: []string{
				"-y",
				"-hide_banner",
				"-nostdin",
				"-i", "${i}?overrun_nonfatal=1&fifo_size=100000000",
				"-map", "0:v:0",
				"-map", "0:a:0",
				"-c:v", "libx264",
				"-preset", "${preset}",
				"-profile:v", "main",
				"-pix_fmt", "yuv420p",
				"-vf", "yadif",
				"-b:v", "${video_bitrate}",
				"-maxrate", "${video_bitrate}",
				"-bufsize", "${video_bufsize}",
				"-c:a", "aac",
				"-b:a", "${audio_bitrate}",
				"-ar", "48000",
				"-ac", "2",
				"-f", "mpegts",
				"${o}?pkt_size=1316",
			},
			Defaults: map[string]string{
				"preset":        "ultrafast",
				"video_bitrate": "4M",
				"video_bufsize": "8M",
				"audio_bitrate": "128k",
			},
		},
	}
}

func BuildArgs(stream Stream, profile Profile) ([]string, error) {
	if err := validateInput(stream); err != nil {
		return nil, fmt.Errorf("input url: %w", err)
	}
	if err := validateURL(stream.OutputURL); err != nil {
		return nil, fmt.Errorf("output url: %w", err)
	}
	if len(profile.Template.Args) > 0 {
		return buildTemplateArgs(stream, profile.Template)
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
	}
	if stream.SourceType == "file" {
		args = append(args, "-re")
	}
	args = append(args, "-i", stream.InputURL)
	if stream.Logo.Enabled {
		if stream.Logo.Path == "" {
			return nil, fmt.Errorf("logo path is required")
		}
		args = append(args, "-i", stream.Logo.Path)
		args = append(args, "-filter_complex", fmt.Sprintf("[%s][1:v:0]overlay=%d:%d[v]", videoMap, stream.Logo.X, stream.Logo.Y))
		args = append(args, "-map", "[v]")
	} else {
		args = append(args, "-map", videoMap)
	}
	if !stream.DisableAudio {
		audioMaps := stream.AudioMaps
		if len(audioMaps) == 0 {
			audioMaps = []string{audioMap}
		}
		for _, item := range audioMaps {
			if item != "" {
				args = append(args, "-map", item)
			}
		}
	}
	args = append(args, "-c:v", profile.Video.Codec)

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

	if !stream.DisableAudio {
		args = append(args, "-c:a", profile.Audio.Codec)
		if profile.Audio.Bitrate != "" && profile.Audio.Codec != "copy" {
			args = append(args, "-b:a", profile.Audio.Bitrate)
		}
	}
	args = append(args, "-f", format, stream.OutputURL)
	return args, nil
}

var templateVariablePattern = regexp.MustCompile(`\$\{([A-Za-z_][A-Za-z0-9_]*)\}`)

func buildTemplateArgs(stream Stream, profile TemplateProfile) ([]string, error) {
	values := make(map[string]string, len(profile.Defaults)+len(stream.Options)+2)
	for key, value := range profile.Defaults {
		values[key] = value
	}
	for key, value := range stream.Options {
		values[key] = value
	}
	values["i"] = stream.InputURL
	values["o"] = stream.OutputURL
	values["logo_path"] = stream.Logo.Path
	if stream.DisableAudio {
		values["audio_enabled"] = "0"
	} else {
		values["audio_enabled"] = "1"
	}

	args := make([]string, 0, len(profile.Args)+4)
	hasProgress := false
	for _, arg := range profile.Args {
		if arg == "" {
			return nil, fmt.Errorf("template args must not contain empty values")
		}
		if arg == "-progress" {
			hasProgress = true
		}
		rendered, err := renderTemplateArg(arg, values)
		if err != nil {
			return nil, err
		}
		args = append(args, rendered)
	}
	if !hasProgress {
		args = append([]string{"-progress", "pipe:1", "-stats_period", "1"}, args...)
	}
	return args, nil
}

func renderTemplateArg(arg string, values map[string]string) (string, error) {
	var missing string
	out := templateVariablePattern.ReplaceAllStringFunc(arg, func(match string) string {
		name := match[2 : len(match)-1]
		value, ok := values[name]
		if !ok {
			missing = name
			return match
		}
		return value
	})
	if missing != "" {
		return "", fmt.Errorf("template variable %q is not defined", missing)
	}
	return out, nil
}

func validateInput(stream Stream) error {
	if stream.InputURL == "" {
		return fmt.Errorf("is required")
	}
	if stream.SourceType == "file" {
		return nil
	}
	return validateURL(stream.InputURL)
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

package ffmpeg

import (
	"fmt"
	"net/url"
	"regexp"
	"strconv"
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
	// ExtraArgs are user-supplied pass-through flags appended just before
	// "-f <format> <output>". Only used by the standard (non-template) path.
	ExtraArgs []string `json:"extra_args,omitempty"`
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
	// GOP sets -g/-keyint_min for libx264; when unset (0), BuildArgs applies
	// a safe default of 50 (matches 25fps content) rather than leaving it to
	// libx264's own default, which is not tuned for multicast IPTV delivery.
	GOP int `json:"gop,omitempty"`
	// FPS adds -r <fps> when set.
	FPS string `json:"fps,omitempty"`
	// Scale adds -vf scale=<value> (or folds into the logo filter_complex
	// chain when a logo overlay is also enabled) when set.
	Scale string `json:"scale,omitempty"`
}

// SystemConfig holds ffmpeg tuning that is not part of a user-editable
// encoding profile: UDP resilience for multicast input, corrupt-packet
// tolerance, and process-level limits. See config.FFmpegConfig, which this
// mirrors field-for-field.
type SystemConfig struct {
	UDPFifoSize        int
	UDPBufferSize      int
	UDPOverrunNonfatal bool
	UDPReuse           bool
	AnalyzeDuration    int
	ProbeSize          int
	Threads            int
	PktSize            int
	DiscardCorrupt     bool
	// LogLevel is the base ffmpeg severity (e.g. "info", "warning", "error").
	// BuildArgs always combines it with the "level" flag so log lines keep
	// their "[level]" tag; empty defaults to "info".
	LogLevel string
}

func logLevelOrDefault(level string) string {
	if level == "" {
		return "info"
	}
	return level
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

func BuildArgs(stream Stream, profile Profile, sys SystemConfig) ([]string, error) {
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

	inputURL, err := augmentMulticastInputURL(stream.InputURL, stream.SourceType, sys)
	if err != nil {
		return nil, fmt.Errorf("input url: %w", err)
	}
	outputURL, err := augmentUDPOutputURL(stream.OutputURL, format, sys)
	if err != nil {
		return nil, fmt.Errorf("output url: %w", err)
	}

	args := []string{
		"-hide_banner",
		"-nostdin",
		// ponytail: -nostats kills ffmpeg's default \r-updated stats line on
		// stderr. Without it that line never gets a trailing \n, so
		// bufio.Scanner in jobs.go buffers it forever and eventually dies with
		// "token too long", which stops draining stderr and hangs ffmpeg.
		// -progress pipe:1 already gives us the same numbers, structured.
		"-nostats",
		// The "level" flag prefixes every line with its real ffmpeg severity
		// (e.g. "[info]", "[error]"), so jobs.go can classify log lines from
		// ground truth instead of guessing from text. The base level itself
		// (sys.LogLevel, default "warning") controls verbosity: "warning"
		// stops ffmpeg from emitting routine per-stream info banners
		// (mapping, codec details) at all, which is most of the volume in
		// the stored log; set it to "info" to get that detail back.
		"-loglevel", "level+" + logLevelOrDefault(sys.LogLevel),
		"-progress", "pipe:1",
		"-stats_period", "1",
	}
	// System-level input tolerance: multicast IPTV sees occasional dropped or
	// corrupt UDP packets, and without these ffmpeg either stalls waiting for
	// a clean GOP or aborts outright. None of this is user-editable per
	// profile - see config.FFmpegConfig / SystemConfig.
	if sys.DiscardCorrupt {
		args = append(args, "-fflags", "+genpts+discardcorrupt")
	} else {
		args = append(args, "-fflags", "+genpts")
	}
	args = append(args, "-err_detect", "ignore_err")
	if sys.AnalyzeDuration > 0 {
		args = append(args, "-analyzeduration", strconv.Itoa(sys.AnalyzeDuration))
	}
	if sys.ProbeSize > 0 {
		args = append(args, "-probesize", strconv.Itoa(sys.ProbeSize))
	}
	if stream.SourceType == "file" {
		args = append(args, "-re")
	}
	args = append(args, "-i", inputURL)
	if stream.Logo.Enabled {
		if stream.Logo.Path == "" {
			return nil, fmt.Errorf("logo path is required")
		}
		args = append(args, "-i", stream.Logo.Path)
		args = append(args, "-filter_complex", logoFilterComplex(videoMap, profile.Video.Scale, stream.Logo))
		args = append(args, "-map", "[v]")
	} else {
		args = append(args, "-map", videoMap)
		if profile.Video.Scale != "" {
			args = append(args, "-vf", "scale="+profile.Video.Scale)
		}
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
	if profile.Video.FPS != "" {
		args = append(args, "-r", profile.Video.FPS)
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
	if profile.Video.Codec == "libx264" {
		gop := profile.Video.GOP
		if gop <= 0 {
			gop = 50
		}
		args = append(args, "-g", strconv.Itoa(gop), "-keyint_min", strconv.Itoa(gop), "-sc_threshold", "0")
		if sys.Threads > 0 {
			args = append(args, "-threads", strconv.Itoa(sys.Threads))
		}
	}

	if !stream.DisableAudio {
		args = append(args, "-c:a", profile.Audio.Codec)
		if profile.Audio.Bitrate != "" && profile.Audio.Codec != "copy" {
			args = append(args, "-b:a", profile.Audio.Bitrate)
		}
	}
	if len(profile.ExtraArgs) > 0 {
		args = append(args, profile.ExtraArgs...)
	}
	args = append(args, "-f", format, outputURL)
	return args, nil
}

func logoFilterComplex(videoMap, scale string, logo LogoOverlay) string {
	if scale == "" {
		return fmt.Sprintf("[%s][1:v:0]overlay=%d:%d[v]", videoMap, logo.X, logo.Y)
	}
	return fmt.Sprintf("[%s]scale=%s[scaled];[scaled][1:v:0]overlay=%d:%d[v]", videoMap, scale, logo.X, logo.Y)
}

// augmentMulticastInputURL adds UDP resilience query params that are system
// tuning, not user-editable stream config - e.g. it preserves an existing
// "localaddr=<interface-ip>" the user set to pick which NIC joins the
// multicast group, only adding to what's already there.
func augmentMulticastInputURL(rawURL, sourceType string, sys SystemConfig) (string, error) {
	if sourceType == "file" {
		return rawURL, nil
	}
	u, err := url.Parse(rawURL)
	if err != nil {
		return "", err
	}
	if u.Scheme != "udp" {
		return rawURL, nil
	}
	q := u.Query()
	if sys.UDPOverrunNonfatal {
		q.Set("overrun_nonfatal", "1")
	}
	if sys.UDPFifoSize > 0 {
		q.Set("fifo_size", strconv.Itoa(sys.UDPFifoSize))
	}
	if sys.UDPBufferSize > 0 {
		q.Set("buffer_size", strconv.Itoa(sys.UDPBufferSize))
	}
	if sys.UDPReuse {
		q.Set("reuse", "1")
	}
	u.RawQuery = q.Encode()
	return u.String(), nil
}

// augmentUDPOutputURL sets pkt_size for MPEG-TS-over-UDP output unless the
// stream's output URL already specifies one explicitly.
func augmentUDPOutputURL(rawURL, format string, sys SystemConfig) (string, error) {
	if format != "mpegts" || sys.PktSize <= 0 {
		return rawURL, nil
	}
	u, err := url.Parse(rawURL)
	if err != nil {
		return "", err
	}
	if u.Scheme != "udp" {
		return rawURL, nil
	}
	q := u.Query()
	if q.Get("pkt_size") == "" {
		q.Set("pkt_size", strconv.Itoa(sys.PktSize))
		u.RawQuery = q.Encode()
	}
	return u.String(), nil
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
		args = append([]string{"-nostats", "-loglevel", "level+info", "-progress", "pipe:1", "-stats_period", "1"}, args...)
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

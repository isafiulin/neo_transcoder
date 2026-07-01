package probe

import (
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"time"
)

type Result struct {
	Format  Format   `json:"format"`
	Streams []Stream `json:"streams"`
}

type Format struct {
	FormatName string `json:"format_name"`
	BitRate    string `json:"bit_rate"`
	Duration   string `json:"duration"`
}

type Stream struct {
	Index         int               `json:"index"`
	CodecType     string            `json:"codec_type"`
	CodecName     string            `json:"codec_name"`
	Width         int               `json:"width,omitempty"`
	Height        int               `json:"height,omitempty"`
	BitRate       string            `json:"bit_rate,omitempty"`
	AvgFrameRate  string            `json:"avg_frame_rate,omitempty"`
	Channels      int               `json:"channels,omitempty"`
	ChannelLayout string            `json:"channel_layout,omitempty"`
	Tags          map[string]string `json:"tags,omitempty"`
}

func Run(ctx context.Context, ffprobePath, inputURL string) (Result, error) {
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	args := []string{
		"-v", "error",
		"-print_format", "json",
		"-show_format",
		"-show_streams",
		inputURL,
	}
	out, err := exec.CommandContext(ctx, ffprobePath, args...).Output()
	if err != nil {
		return Result{}, fmt.Errorf("ffprobe: %w", err)
	}
	return Parse(out)
}

func Parse(data []byte) (Result, error) {
	var result Result
	if err := json.Unmarshal(data, &result); err != nil {
		return Result{}, err
	}
	return result, nil
}

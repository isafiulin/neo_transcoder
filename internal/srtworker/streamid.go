package srtworker

import (
	"fmt"
	"net/url"
	"strings"
)

func clientIDFromStreamID(streamID string) (string, error) {
	streamID = strings.TrimSpace(streamID)
	if streamID == "" {
		return "", fmt.Errorf("Stream ID is required")
	}
	if !strings.HasPrefix(streamID, "#!::") {
		return streamID, nil
	}
	for _, field := range strings.Split(strings.TrimPrefix(streamID, "#!::"), ",") {
		key, value, ok := strings.Cut(field, "=")
		if !ok || key != "u" {
			continue
		}
		decoded, err := url.QueryUnescape(value)
		if err != nil || decoded == "" {
			return "", fmt.Errorf("invalid client ID in Stream ID")
		}
		return decoded, nil
	}
	return "", fmt.Errorf("Stream ID must include u=<client-id>")
}

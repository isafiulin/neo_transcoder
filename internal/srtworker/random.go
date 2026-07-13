package srtworker

import (
	"crypto/rand"
	"encoding/base64"
)

func randomID(prefix string) (string, error) {
	data := make([]byte, 12)
	if _, err := rand.Read(data); err != nil {
		return "", err
	}
	return prefix + base64.RawURLEncoding.EncodeToString(data), nil
}

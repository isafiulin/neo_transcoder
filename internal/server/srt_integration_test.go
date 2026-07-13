package server

import (
	"bufio"
	"bytes"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"neotranscoder/internal/config"
	"neotranscoder/internal/srtrelay"
)

func TestSRTAPIAuthAndCredentialLifecycle(t *testing.T) {
	server, httpServer := newHTTPTestServer(t)

	response := request(t, httpServer, http.MethodGet, "/api/srt/relays", "", nil)
	assertStatus(t, response, http.StatusUnauthorized)

	response = request(t, httpServer, http.MethodPost, "/api/auth/login", "", map[string]any{
		"username": "admin", "password": "wrong",
	})
	assertStatus(t, response, http.StatusUnauthorized)

	token := loginToken(t, httpServer)
	response = request(t, httpServer, http.MethodGet, "/api/auth/verify", token, nil)
	assertStatus(t, response, http.StatusOK)

	response = request(t, httpServer, http.MethodPost, "/api/srt/relays", token, map[string]any{
		"id": "news-srt", "input_url": "udp://239.10.10.1:1234",
		"bind_address": "0.0.0.0", "port": 9000, "enabled": true,
		"unexpected": true,
	})
	assertStatus(t, response, http.StatusBadRequest)

	response = request(t, httpServer, http.MethodPost, "/api/srt/relays", token, relayPayload())
	assertStatus(t, response, http.StatusOK)
	var relay srtrelay.RelayView
	decodeResponse(t, response, &relay)
	if relay.Config.InputTimeoutSeconds != 10 || relay.State.Status != "stopped" {
		t.Fatalf("created relay = %+v", relay)
	}

	response = request(t, httpServer, http.MethodPost, "/api/srt/relays/news-srt/start", token, nil)
	assertStatus(t, response, http.StatusBadRequest)

	clientPayload := map[string]any{
		"id": "partner-a", "name": "Partner A", "enabled": true,
		"allowed_relay_ids": []string{"news-srt"},
		"allowed_cidrs":     []string{"203.0.113.10"}, "max_sessions": 1,
	}
	response = request(t, httpServer, http.MethodPost, "/api/srt/clients", token, clientPayload)
	assertStatus(t, response, http.StatusCreated)
	var created srtrelay.ClientCredential
	decodeResponse(t, response, &created)
	if len(created.Passphrase) != 43 || created.Client.AllowedCIDRs[0] != "203.0.113.10/32" {
		t.Fatalf("created credential = %+v", created)
	}

	response = request(t, httpServer, http.MethodPost, "/api/srt/clients", token, clientPayload)
	assertStatus(t, response, http.StatusConflict)

	response = request(t, httpServer, http.MethodGet, "/api/srt/clients", token, nil)
	assertStatus(t, response, http.StatusOK)
	body := readBody(t, response)
	if bytes.Contains(body, []byte("passphrase")) || bytes.Contains(body, []byte(created.Passphrase)) {
		t.Fatalf("client list leaked a credential: %s", body)
	}

	response = request(t, httpServer, http.MethodDelete, "/api/srt/relays/news-srt", token, nil)
	assertStatus(t, response, http.StatusBadRequest)

	response = request(t, httpServer, http.MethodPost, "/api/srt/clients/partner-a/rotate-key", token, nil)
	assertStatus(t, response, http.StatusOK)
	var rotated srtrelay.ClientCredential
	decodeResponse(t, response, &rotated)
	if rotated.Passphrase == created.Passphrase || rotated.Client.KeyVersion != 2 {
		t.Fatalf("rotated credential = %+v", rotated)
	}

	response = request(t, httpServer, http.MethodGet, "/api/srt/audit?client_id=partner-a&limit=20", token, nil)
	assertStatus(t, response, http.StatusOK)
	var audit []srtrelay.AuditEvent
	decodeResponse(t, response, &audit)
	if len(audit) < 2 || audit[0].Actor != "admin" || audit[0].Type != "client_key_rotated" {
		t.Fatalf("operator audit = %+v", audit)
	}

	response = request(t, httpServer, http.MethodDelete, "/api/srt/clients/partner-a", token, nil)
	assertStatus(t, response, http.StatusNoContent)
	response = request(t, httpServer, http.MethodDelete, "/api/srt/relays/news-srt", token, nil)
	assertStatus(t, response, http.StatusNoContent)

	if got := len(server.srtStore.ListRelays()); got != 0 {
		t.Fatalf("relays after delete = %d", got)
	}
}

func TestSRTAPIUnencryptedClientRequiresRestrictedACL(t *testing.T) {
	_, httpServer := newHTTPTestServer(t)
	token := loginToken(t, httpServer)
	response := request(t, httpServer, http.MethodPost, "/api/srt/relays", token, relayPayload())
	assertStatus(t, response, http.StatusOK)

	payload := map[string]any{
		"id": "legacy-partner", "name": "Legacy Partner", "enabled": true,
		"encryption_mode":   srtrelay.EncryptionNone,
		"allowed_relay_ids": []string{"news-srt"},
		"allowed_cidrs":     []string{"0.0.0.0/0"}, "max_sessions": 1,
	}
	response = request(t, httpServer, http.MethodPost, "/api/srt/clients", token, payload)
	assertStatus(t, response, http.StatusBadRequest)

	payload["allowed_cidrs"] = []string{"203.0.113.20/32"}
	response = request(t, httpServer, http.MethodPost, "/api/srt/clients", token, payload)
	assertStatus(t, response, http.StatusCreated)
	var created srtrelay.ClientCredential
	decodeResponse(t, response, &created)
	if created.Passphrase != "" || created.Client.EncryptionMode != srtrelay.EncryptionNone {
		t.Fatalf("unencrypted credential = %+v", created)
	}

	response = request(t, httpServer, http.MethodPost, "/api/srt/clients/legacy-partner/rotate-key", token, nil)
	assertStatus(t, response, http.StatusBadRequest)
}

func TestSRTAPICreatesPublishCallerWithOneTimeKey(t *testing.T) {
	_, httpServer := newHTTPTestServer(t)
	token := loginToken(t, httpServer)
	payload := map[string]any{
		"id": "partner-publish", "name": "Partner publish", "direction": "publish",
		"input_url": "udp://239.10.10.2:1234", "destination_address": "203.0.113.50",
		"destination_port": 9000, "stream_id": "channel-1",
		"encryption_mode": "aes-256", "latency_ms": 800, "payload_size": 1316,
		"input_timeout_seconds": 10, "enabled": true,
	}
	response := request(t, httpServer, http.MethodPost, "/api/srt/relays", token, payload)
	assertStatus(t, response, http.StatusOK)
	var created srtrelay.RelayView
	decodeResponse(t, response, &created)
	if created.Config.Direction != srtrelay.DirectionPublish || len(created.Passphrase) != 43 {
		t.Fatalf("publish relay = %+v", created)
	}
	response = request(t, httpServer, http.MethodGet, "/api/srt/relays", token, nil)
	body := readBody(t, response)
	if bytes.Contains(body, []byte(created.Passphrase)) || bytes.Contains(body, []byte("passphrase")) {
		t.Fatalf("relay list leaked publish credential: %s", body)
	}
}

func TestAuthRejectsWrongTokenTypesAndInvalidatesChangedPassword(t *testing.T) {
	_, httpServer := newHTTPTestServer(t)
	token, refresh := loginPair(t, httpServer)

	response := request(t, httpServer, http.MethodPost, "/api/auth/refresh", "", map[string]any{
		"refresh_token": token,
	})
	assertStatus(t, response, http.StatusUnauthorized)

	response = request(t, httpServer, http.MethodPost, "/api/auth/change-password", token, map[string]any{
		"current_password": "incorrect", "new_password": "new-secure-password",
	})
	assertStatus(t, response, http.StatusBadRequest)

	response = request(t, httpServer, http.MethodPost, "/api/auth/change-password", token, map[string]any{
		"current_password": "123456", "new_password": "new-secure-password",
	})
	assertStatus(t, response, http.StatusOK)

	response = request(t, httpServer, http.MethodGet, "/api/auth/verify", token, nil)
	assertStatus(t, response, http.StatusUnauthorized)
	response = request(t, httpServer, http.MethodPost, "/api/auth/refresh", "", map[string]any{
		"refresh_token": refresh,
	})
	assertStatus(t, response, http.StatusUnauthorized)

	response = request(t, httpServer, http.MethodPost, "/api/auth/login", "", map[string]any{
		"username": "admin", "password": "new-secure-password",
	})
	assertStatus(t, response, http.StatusOK)
}

func TestSRTSSEEmitsRelayEvent(t *testing.T) {
	_, httpServer := newHTTPTestServer(t)
	token := loginToken(t, httpServer)
	req, err := http.NewRequest(http.MethodGet, httpServer.URL+"/api/events", nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Authorization", "Bearer "+token)
	response, err := httpServer.Client().Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	assertStatus(t, response, http.StatusOK)

	lines := make(chan string, 1)
	go func() {
		scanner := bufio.NewScanner(response.Body)
		for scanner.Scan() {
			if strings.HasPrefix(scanner.Text(), "event: ") {
				lines <- scanner.Text()
				return
			}
		}
	}()
	created := request(t, httpServer, http.MethodPost, "/api/srt/relays", token, relayPayload())
	assertStatus(t, created, http.StatusOK)
	_ = created.Body.Close()
	select {
	case line := <-lines:
		if line != "event: srt_relay_saved" {
			t.Fatalf("SSE event = %q", line)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for SRT SSE event")
	}
}

func TestCoreAPIPositiveAndNegativeLifecycle(t *testing.T) {
	server, httpServer := newHTTPTestServer(t)
	server.cfg.FFmpeg.Path = filepath.Join(t.TempDir(), "missing-ffmpeg")
	server.cfg.FFmpeg.FFprobePath = filepath.Join(t.TempDir(), "missing-ffprobe")

	response := request(t, httpServer, http.MethodGet, "/api/health", "", nil)
	assertStatus(t, response, http.StatusOK)
	var health map[string]any
	decodeResponse(t, response, &health)
	if health["service"] != "neotranscoder" {
		t.Fatalf("health = %+v", health)
	}

	token := loginToken(t, httpServer)
	response = request(t, httpServer, http.MethodGet, "/api/doctor", token, nil)
	assertStatus(t, response, http.StatusServiceUnavailable)
	_ = response.Body.Close()

	response = request(t, httpServer, http.MethodPost, "/api/users", token, map[string]any{
		"username": "ab", "password": "123456",
	})
	assertStatus(t, response, http.StatusBadRequest)
	_ = response.Body.Close()
	response = request(t, httpServer, http.MethodPost, "/api/users", token, map[string]any{
		"username": "operator", "password": "secure-password",
	})
	assertStatus(t, response, http.StatusCreated)
	_ = response.Body.Close()
	response = request(t, httpServer, http.MethodPost, "/api/users", token, map[string]any{
		"username": "operator", "password": "secure-password",
	})
	assertStatus(t, response, http.StatusBadRequest)
	_ = response.Body.Close()
	response = request(t, httpServer, http.MethodDelete, "/api/users/admin", token, nil)
	assertStatus(t, response, http.StatusBadRequest)
	_ = response.Body.Close()

	response = request(t, httpServer, http.MethodPost, "/api/streams", token, map[string]any{
		"id": "bad-stream", "input_url": "udp://239.1.1.1:1234",
		"output_url": "udp://239.2.2.2:1234", "profile_name": "missing-profile",
	})
	assertStatus(t, response, http.StatusBadRequest)
	_ = response.Body.Close()
	response = request(t, httpServer, http.MethodPost, "/api/streams", token, map[string]any{
		"id": "channel-1", "name": "Channel 1",
		"input_url": "udp://239.1.1.1:1234", "output_url": "udp://239.2.2.2:1234",
		"enabled": true,
	})
	assertStatus(t, response, http.StatusOK)
	_ = response.Body.Close()

	response = request(t, httpServer, http.MethodGet, "/api/streams/channel-1/ffmpeg-command", token, nil)
	assertStatus(t, response, http.StatusOK)
	var command struct {
		Path string   `json:"path"`
		Args []string `json:"args"`
	}
	decodeResponse(t, response, &command)
	if command.Path != server.cfg.FFmpeg.Path || len(command.Args) == 0 {
		t.Fatalf("ffmpeg command = %+v", command)
	}
	response = request(t, httpServer, http.MethodPost, "/api/streams/channel-1/start", token, nil)
	assertStatus(t, response, http.StatusBadRequest)
	_ = response.Body.Close()

	response = request(t, httpServer, http.MethodPost, "/api/probe", token, map[string]any{
		"input_url": "udp://239.1.1.1:1234",
	})
	assertStatus(t, response, http.StatusBadRequest)
	_ = response.Body.Close()

	response = request(t, httpServer, http.MethodDelete, "/api/streams/channel-1", token, nil)
	assertStatus(t, response, http.StatusNoContent)
	_ = response.Body.Close()
	response = request(t, httpServer, http.MethodDelete, "/api/streams/channel-1", token, nil)
	assertStatus(t, response, http.StatusNotFound)
	_ = response.Body.Close()
	response = request(t, httpServer, http.MethodDelete, "/api/users/operator", token, nil)
	assertStatus(t, response, http.StatusNoContent)
	_ = response.Body.Close()

	response = request(t, httpServer, http.MethodGet, "/srt/relays", "", nil)
	assertStatus(t, response, http.StatusOK)
	body := readBody(t, response)
	if !bytes.Contains(body, []byte("<html")) {
		t.Fatalf("SPA fallback did not return HTML: %.100s", body)
	}
}

func newHTTPTestServer(t *testing.T) (*Server, *httptest.Server) {
	t.Helper()
	dir := t.TempDir()
	cfg := config.Default()
	cfg.Storage.Path = filepath.Join(dir, "state.json")
	cfg.SRT.StatePath = filepath.Join(dir, "srt-state.json")
	cfg.SRT.MasterKeyPath = filepath.Join(dir, "srt-master.key")
	cfg.SRT.AuditDir = filepath.Join(dir, "audit")
	cfg.SRT.WorkerPath = filepath.Join(dir, "missing-srt-worker")
	server, err := New(cfg, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err != nil {
		t.Fatal(err)
	}
	httpServer := httptest.NewServer(server.handler())
	t.Cleanup(httpServer.Close)
	return server, httpServer
}

func relayPayload() map[string]any {
	return map[string]any{
		"id": "news-srt", "name": "News SRT",
		"input_url": "udp://239.10.10.1:1234", "bind_address": "0.0.0.0",
		"port": 9000, "latency_ms": 800, "payload_size": 1316,
		"max_clients": 16, "enabled": true,
	}
}

func loginToken(t *testing.T, server *httptest.Server) string {
	t.Helper()
	token, _ := loginPair(t, server)
	return token
}

func loginPair(t *testing.T, server *httptest.Server) (string, string) {
	t.Helper()
	response := request(t, server, http.MethodPost, "/api/auth/login", "", map[string]any{
		"username": "admin", "password": "123456",
	})
	assertStatus(t, response, http.StatusOK)
	var payload struct {
		AccessToken  string `json:"access_token"`
		RefreshToken string `json:"refresh_token"`
	}
	decodeResponse(t, response, &payload)
	return payload.AccessToken, payload.RefreshToken
}

func request(t *testing.T, server *httptest.Server, method, path, token string, payload any) *http.Response {
	t.Helper()
	var body io.Reader
	if payload != nil {
		data, err := json.Marshal(payload)
		if err != nil {
			t.Fatal(err)
		}
		body = bytes.NewReader(data)
	}
	req, err := http.NewRequest(method, server.URL+path, body)
	if err != nil {
		t.Fatal(err)
	}
	if payload != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	response, err := server.Client().Do(req)
	if err != nil {
		t.Fatal(err)
	}
	return response
}

func assertStatus(t *testing.T, response *http.Response, expected int) {
	t.Helper()
	if response.StatusCode != expected {
		body := readBody(t, response)
		t.Fatalf("status = %d, want %d: %s", response.StatusCode, expected, body)
	}
}

func decodeResponse(t *testing.T, response *http.Response, target any) {
	t.Helper()
	defer response.Body.Close()
	if err := json.NewDecoder(response.Body).Decode(target); err != nil {
		t.Fatal(err)
	}
}

func readBody(t *testing.T, response *http.Response) []byte {
	t.Helper()
	defer response.Body.Close()
	body, err := io.ReadAll(response.Body)
	if err != nil {
		t.Fatal(err)
	}
	return body
}

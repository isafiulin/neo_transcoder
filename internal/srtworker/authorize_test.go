package srtworker

import (
	"testing"

	"neotranscoder/internal/srtrelay"
)

func TestAuthorizeRejectsInvalidIdentityIPAndSessionLimits(t *testing.T) {
	worker, err := newWorker(srtrelay.WorkerConfig{
		Relay: srtrelay.Relay{ID: "news-srt", MaxClients: 1},
		Clients: []srtrelay.WorkerClient{{
			ID: "partner-a", Passphrase: "secure-test-passphrase",
			AllowedCIDRs: []string{"203.0.113.0/24"}, MaxSessions: 1,
		}},
	})
	if err != nil {
		t.Fatal(err)
	}
	tests := []struct {
		ip       string
		streamID string
		code     int
	}{
		{ip: "203.0.113.10", streamID: "", code: 400},
		{ip: "203.0.113.10", streamID: "unknown", code: 404},
		{ip: "198.51.100.10", streamID: "partner-a", code: 403},
		{ip: "invalid-ip", streamID: "partner-a", code: 403},
	}
	for _, test := range tests {
		if _, code := worker.authorize(test.ip, 5000, test.streamID); code != test.code {
			t.Fatalf("authorize(%q, %q) code = %d, want %d", test.ip, test.streamID, code, test.code)
		}
	}
	secret, code := worker.authorize("203.0.113.10", 5001, "partner-a")
	if code != 0 || secret != "secure-test-passphrase" {
		t.Fatalf("valid authorization secret=%q code=%d", secret, code)
	}
	duplicateSecret, duplicateCode := worker.authorize("203.0.113.10", 5001, "partner-a")
	if duplicateCode != 0 || duplicateSecret != secret {
		t.Fatalf("duplicate handshake callback secret=%q code=%d", duplicateSecret, duplicateCode)
	}
	if len(worker.pending) != 1 || worker.reservations["partner-a"] != 1 {
		t.Fatalf("duplicate handshake changed reservations: pending=%d reservations=%d", len(worker.pending), worker.reservations["partner-a"])
	}
	if _, code := worker.authorize("203.0.113.11", 5002, "partner-a"); code != 429 {
		t.Fatalf("concurrent session reservation code = %d, want 429", code)
	}
	worker.expireAttempt(attemptKey("203.0.113.10", 5001, "partner-a"))
	if _, code := worker.authorize("203.0.113.11", 5002, "#!::u=partner-a,m=request"); code != 0 {
		t.Fatalf("authorization after reservation expiry code = %d", code)
	}
}

func TestNewWorkerRejectsInvalidClientSecretsAndCIDRs(t *testing.T) {
	tests := []srtrelay.WorkerClient{
		{ID: "partner-a", Passphrase: "short", AllowedCIDRs: []string{"203.0.113.0/24"}, MaxSessions: 1},
		{ID: "partner-a", Passphrase: "secure-test-passphrase", AllowedCIDRs: []string{"invalid"}, MaxSessions: 1},
		{ID: "partner-a", EncryptionMode: "optional", AllowedCIDRs: []string{"203.0.113.0/24"}, MaxSessions: 1},
		{ID: "partner-a", EncryptionMode: srtrelay.EncryptionNone, Passphrase: "must-not-exist", AllowedCIDRs: []string{"203.0.113.0/24"}, MaxSessions: 1},
	}
	for _, client := range tests {
		_, err := newWorker(srtrelay.WorkerConfig{
			Relay: srtrelay.Relay{MaxClients: 1}, Clients: []srtrelay.WorkerClient{client},
		})
		if err == nil {
			t.Fatalf("expected invalid worker client rejection: %+v", client)
		}
	}
}

func TestAuthorizeUnencryptedClientReturnsNoSecret(t *testing.T) {
	worker, err := newWorker(srtrelay.WorkerConfig{
		Relay: srtrelay.Relay{ID: "legacy-srt", MaxClients: 1},
		Clients: []srtrelay.WorkerClient{{
			ID: "legacy-partner", EncryptionMode: srtrelay.EncryptionNone,
			AllowedCIDRs: []string{"203.0.113.20/32"}, MaxSessions: 1,
		}},
	})
	if err != nil {
		t.Fatal(err)
	}
	secret, code := worker.authorize("203.0.113.20", 5000, "legacy-partner")
	if code != 0 || secret != "" {
		t.Fatalf("unencrypted authorization secret=%q code=%d", secret, code)
	}
	worker.expireAttempt(attemptKey("203.0.113.20", 5000, "legacy-partner"))
	if _, code := worker.authorize("203.0.113.21", 5001, "legacy-partner"); code != 403 {
		t.Fatalf("unencrypted client outside ACL code = %d, want 403", code)
	}
}

func TestAuthorizeMissingStreamIDCompatibilityUsesExplicitDefault(t *testing.T) {
	worker, err := newWorker(srtrelay.WorkerConfig{
		Relay: srtrelay.Relay{
			ID: "vlc-srt", Direction: srtrelay.DirectionListener, MaxClients: 2,
			AllowMissingStreamID: true, DefaultClientID: "vlc-client",
		},
		Clients: []srtrelay.WorkerClient{{
			ID: "vlc-client", Passphrase: "secure-test-passphrase",
			AllowedCIDRs: []string{"203.0.113.10/32"}, MaxSessions: 1,
		}},
	})
	if err != nil {
		t.Fatal(err)
	}
	secret, code := worker.authorize("203.0.113.10", 5000, "")
	if code != 0 || secret != "secure-test-passphrase" {
		t.Fatalf("compatibility authorization secret=%q code=%d", secret, code)
	}
	pending := worker.pending[attemptKey("203.0.113.10", 5000, "")]
	if pending.clientID != "vlc-client" {
		t.Fatalf("pending default client = %q", pending.clientID)
	}
	duplicateSecret, duplicateCode := worker.authorize("203.0.113.10", 5000, "")
	if duplicateCode != 0 || duplicateSecret != secret || worker.reservations["vlc-client"] != 1 {
		t.Fatalf("compatibility retry secret=%q code=%d reservations=%d", duplicateSecret, duplicateCode, worker.reservations["vlc-client"])
	}
	worker.expireAttempt(attemptKey("203.0.113.10", 5000, ""))
	if _, code := worker.authorize("203.0.113.11", 5001, ""); code != 403 {
		t.Fatalf("compatibility mode bypassed IP ACL: code=%d", code)
	}
}

func TestNewWorkerRejectsUnavailableCompatibilityDefault(t *testing.T) {
	_, err := newWorker(srtrelay.WorkerConfig{
		Relay: srtrelay.Relay{
			Direction: srtrelay.DirectionListener, MaxClients: 1,
			AllowMissingStreamID: true, DefaultClientID: "missing-client",
		},
	})
	if err == nil {
		t.Fatal("worker accepted an unavailable compatibility default client")
	}
}

func TestListenerMinimumVersion(t *testing.T) {
	strict := listenerMinimumVersion(srtrelay.Relay{})
	if strict != 0x010300 {
		t.Fatalf("strict minimum version = %#x, want 0x010300", strict)
	}
	compatible := listenerMinimumVersion(srtrelay.Relay{AllowMissingStreamID: true})
	if compatible != 0x010000 {
		t.Fatalf("compatibility minimum version = %#x, want 0x010000", compatible)
	}
}

func TestListenerEncryptionPolicyAllowsIPACLOnlyClients(t *testing.T) {
	aes := srtrelay.WorkerClient{ID: "aes", EncryptionMode: srtrelay.EncryptionAES256}
	none := srtrelay.WorkerClient{ID: "vlc", EncryptionMode: srtrelay.EncryptionNone}
	if !listenerEnforcesEncryption([]srtrelay.WorkerClient{aes}) {
		t.Fatal("AES-only listener should enforce encryption globally")
	}
	if listenerEnforcesEncryption([]srtrelay.WorkerClient{aes, none}) {
		t.Fatal("mixed listener should allow unencrypted handshakes")
	}
}

func TestNewWorkerValidatesPublishCredentialMode(t *testing.T) {
	base := srtrelay.Relay{Direction: srtrelay.DirectionPublish, EncryptionMode: srtrelay.EncryptionAES256}
	if _, err := newWorker(srtrelay.WorkerConfig{Relay: base, PublishPassphrase: "short"}); err == nil {
		t.Fatal("encrypted publish worker accepted a short passphrase")
	}
	base.EncryptionMode = srtrelay.EncryptionNone
	if _, err := newWorker(srtrelay.WorkerConfig{Relay: base, PublishPassphrase: "unexpected-secret"}); err == nil {
		t.Fatal("unencrypted publish worker accepted a passphrase")
	}
	if _, err := newWorker(srtrelay.WorkerConfig{Relay: base}); err != nil {
		t.Fatalf("valid unencrypted publish worker: %v", err)
	}
}

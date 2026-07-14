package srtrelay

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestRelayAndClientCredentialLifecycle(t *testing.T) {
	store := testStore(t)
	relay, err := store.UpsertRelay(Relay{
		ID:          "news-hd",
		Name:        "News HD",
		InputURL:    "udp://239.1.1.10:1234?localaddr=10.0.0.5",
		BindAddress: "0.0.0.0",
		Port:        9000,
		Enabled:     true,
	})
	if err != nil {
		t.Fatal(err)
	}
	if relay.Config.LatencyMS != 800 || relay.Config.PayloadSize != 1316 || relay.Config.InputTimeoutSeconds != 10 {
		t.Fatalf("defaults not applied: %+v", relay.Config)
	}

	created, err := store.UpsertClient(Client{
		ID:              "partner-a",
		Name:            "Partner A",
		Enabled:         true,
		AllowedRelayIDs: []string{"news-hd"},
		AllowedCIDRs:    []string{"203.0.113.10"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(created.Passphrase) != 43 {
		t.Fatalf("passphrase length = %d", len(created.Passphrase))
	}
	if created.Client.EncryptionMode != EncryptionAES256 {
		t.Fatalf("default encryption mode = %q", created.Client.EncryptionMode)
	}
	if got := created.Client.AllowedCIDRs[0]; got != "203.0.113.10/32" {
		t.Fatalf("allowed CIDR = %q", got)
	}
	rotated, err := store.RotateClientKey("partner-a")
	if err != nil {
		t.Fatal(err)
	}
	if rotated.Passphrase == created.Passphrase || rotated.Client.KeyVersion != 2 {
		t.Fatal("key rotation did not change the credential")
	}
	workerClients := store.WorkerClients("news-hd")
	if len(workerClients) != 1 || workerClients[0].Passphrase != rotated.Passphrase {
		t.Fatalf("worker clients = %+v", workerClients)
	}
}

func TestUnencryptedClientUsesIPACLWithoutCredential(t *testing.T) {
	store := testStore(t)
	_, err := store.UpsertRelay(Relay{
		ID: "legacy-srt", InputURL: "udp://239.1.1.20:1234",
		BindAddress: "0.0.0.0", Port: 9010,
	})
	if err != nil {
		t.Fatal(err)
	}
	created, err := store.UpsertClient(Client{
		ID: "legacy-partner", Enabled: true, EncryptionMode: EncryptionNone,
		AllowedRelayIDs: []string{"legacy-srt"}, AllowedCIDRs: []string{"203.0.113.20"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if created.Passphrase != "" || created.Client.EncryptionMode != EncryptionNone {
		t.Fatalf("unencrypted credential = %+v", created)
	}
	workerClients := store.WorkerClients("legacy-srt")
	if len(workerClients) != 1 || workerClients[0].Passphrase != "" || workerClients[0].EncryptionMode != EncryptionNone {
		t.Fatalf("worker clients = %+v", workerClients)
	}
	if _, err := store.RotateClientKey("legacy-partner"); err == nil {
		t.Fatal("unencrypted client key rotation succeeded")
	}
	created.Client.EncryptionMode = EncryptionAES256
	reenabled, err := store.UpsertClient(created.Client)
	if err != nil {
		t.Fatal(err)
	}
	if len(reenabled.Passphrase) != 43 || reenabled.Client.KeyVersion != 2 {
		t.Fatalf("re-enabled encryption credential = %+v", reenabled)
	}
}

func TestListenerCompatibilityDefaultClientLifecycle(t *testing.T) {
	store := testStore(t)
	base := Relay{
		ID: "vlc-srt", InputURL: "udp://239.1.1.21:1234",
		BindAddress: "0.0.0.0", Port: 9011,
	}
	if _, err := store.UpsertRelay(base); err != nil {
		t.Fatal(err)
	}
	base.AllowMissingStreamID = true
	base.DefaultClientID = "vlc-client"
	if _, err := store.UpsertRelay(base); err == nil {
		t.Fatal("compatibility mode accepted a missing default client")
	}
	credential, err := store.UpsertClient(Client{
		ID: "vlc-client", Enabled: true,
		AllowedRelayIDs: []string{"vlc-srt"},
		AllowedCIDRs:    []string{"203.0.113.10"},
	})
	if err != nil {
		t.Fatal(err)
	}
	view, err := store.UpsertRelay(base)
	if err != nil {
		t.Fatal(err)
	}
	if !view.Config.AllowMissingStreamID || view.Config.DefaultClientID != "vlc-client" {
		t.Fatalf("compatibility settings = %+v", view.Config)
	}
	credential.Client.Enabled = false
	if _, err := store.UpsertClient(credential.Client); err == nil {
		t.Fatal("default client was disabled while compatibility mode uses it")
	}
	if _, err := store.DeleteClient("vlc-client"); err == nil {
		t.Fatal("compatibility default client was deleted")
	}
}

func TestPublishRelayCredentialAndValidation(t *testing.T) {
	store := testStore(t)
	created, err := store.UpsertRelay(Relay{
		ID: "partner-publish", Direction: DirectionPublish,
		InputURL: "udp://239.1.1.30:1234", DestinationAddress: "203.0.113.50",
		DestinationPort: 9000, StreamID: "channel-1", EncryptionMode: EncryptionAES256,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(created.Passphrase) != 43 || created.Config.KeyVersion != 1 {
		t.Fatalf("publish credential = %+v", created)
	}
	loaded, _ := store.GetRelay("partner-publish")
	if loaded.Passphrase != "" || store.PublishPassphrase("partner-publish") != created.Passphrase {
		t.Fatal("publish credential was leaked or changed")
	}
	_, err = store.UpsertRelay(Relay{
		ID: "bad-publish", Direction: DirectionPublish,
		InputURL: "udp://239.1.1.31:1234", DestinationAddress: "partner.example",
		DestinationPort: 9000, StreamID: "channel-2", EncryptionMode: EncryptionNone,
	})
	if err == nil {
		t.Fatal("publish relay accepted a non-literal destination")
	}
	_, err = store.UpsertClient(Client{
		ID: "invalid-client", AllowedRelayIDs: []string{"partner-publish"},
		AllowedCIDRs: []string{"203.0.113.50"},
	})
	if err == nil {
		t.Fatal("listener client was assigned to a publish relay")
	}
}

func TestSlowEventSubscriberDoesNotBlockStateUpdates(t *testing.T) {
	store := testStore(t)
	ctx, cancel := context.WithCancel(context.Background())
	events := store.Subscribe(ctx)
	for index := 0; index < 1000; index++ {
		store.UpdateState("relay-a", func(state RelayState) RelayState {
			state.InputPackets = int64(index)
			return state
		})
	}
	cancel()
	deadline := time.After(time.Second)
	for {
		select {
		case _, ok := <-events:
			if !ok {
				return
			}
		case <-deadline:
			t.Fatal("subscriber did not close after cancellation")
		}
	}
}

func TestCompletedSessionHistoryHasMemoryCeiling(t *testing.T) {
	store := testStore(t)
	store.mu.Lock()
	for index := 0; index < 1005; index++ {
		disconnected := time.Now().UTC().Add(time.Duration(index) * time.Millisecond)
		session := Session{
			ID: fmt.Sprintf("session-%d", index), ConnectedAt: disconnected.Add(-time.Second),
			DisconnectedAt: &disconnected,
		}
		store.sessions[session.ID] = session
	}
	store.pruneSessionsLocked()
	store.mu.Unlock()
	if got := len(store.ListSessions(false)); got != 1000 {
		t.Fatalf("completed session history = %d, want 1000", got)
	}
}

func TestRelayRejectsDuplicateListener(t *testing.T) {
	store := testStore(t)
	for _, id := range []string{"relay-one", "relay-two"} {
		_, err := store.UpsertRelay(Relay{
			ID: id, InputURL: "udp://239.1.1.10:1234",
			BindAddress: "0.0.0.0", Port: 9000,
		})
		if id == "relay-one" && err != nil {
			t.Fatal(err)
		}
		if id == "relay-two" && err == nil {
			t.Fatal("expected duplicate listener rejection")
		}
	}
}

func TestClientValidationRejectsMissingOrUnsafeACL(t *testing.T) {
	store := testStore(t)
	_, err := store.UpsertRelay(Relay{
		ID: "news-srt", InputURL: "udp://239.1.1.10:1234",
		BindAddress: "0.0.0.0", Port: 9000,
	})
	if err != nil {
		t.Fatal(err)
	}
	tests := []Client{
		{ID: "short", AllowedRelayIDs: []string{"missing"}, AllowedCIDRs: []string{"203.0.113.1"}},
		{ID: "no-cidrs", AllowedRelayIDs: []string{"news-srt"}},
		{ID: "bad-cidr", AllowedRelayIDs: []string{"news-srt"}, AllowedCIDRs: []string{"not-an-ip"}},
		{ID: "bad-limit", AllowedRelayIDs: []string{"news-srt"}, AllowedCIDRs: []string{"203.0.113.1"}, MaxSessions: 1001},
		{ID: "bad-mode", EncryptionMode: "optional", AllowedRelayIDs: []string{"news-srt"}, AllowedCIDRs: []string{"203.0.113.1"}},
		{ID: "open-ipv4", EncryptionMode: EncryptionNone, AllowedRelayIDs: []string{"news-srt"}, AllowedCIDRs: []string{"0.0.0.0/0"}},
		{ID: "open-ipv6", EncryptionMode: EncryptionNone, AllowedRelayIDs: []string{"news-srt"}, AllowedCIDRs: []string{"::/0"}},
	}
	for _, client := range tests {
		if _, err := store.UpsertClient(client); err == nil {
			t.Fatalf("expected client %q validation error", client.ID)
		}
	}
}

func TestActiveSessionPreventsClientDeletion(t *testing.T) {
	store := testStore(t)
	createManagerRelayAndClient(t, store)
	now := time.Now().UTC()
	session := Session{
		ID: "session-1", RelayID: "news-srt", ClientID: "partner-a",
		RemoteIP: "203.0.113.10", ConnectedAt: now,
	}
	store.ApplyWorkerEvent("news-srt", WorkerEvent{Type: "session_connected", Session: &session})
	if _, err := store.DeleteClient("partner-a"); err == nil {
		t.Fatal("active client was deleted")
	}
	disconnected := now.Add(time.Second)
	session.DisconnectedAt = &disconnected
	store.ApplyWorkerEvent("news-srt", WorkerEvent{Type: "session_disconnected", Session: &session})
	deleted, err := store.DeleteClient("partner-a")
	if err != nil || !deleted {
		t.Fatalf("delete disconnected client: deleted=%v err=%v", deleted, err)
	}
}

func TestCloseRelaySessionsClearsActiveSessions(t *testing.T) {
	store := testStore(t)
	createManagerRelayAndClient(t, store)
	now := time.Now().UTC()
	session := Session{
		ID: "session-1", RelayID: "news-srt", ClientID: "partner-a",
		RemoteIP: "203.0.113.10", ConnectedAt: now,
	}
	store.ApplyWorkerEvent("news-srt", WorkerEvent{Type: "session_connected", Session: &session})
	closed := store.CloseRelaySessions("news-srt", "worker exited", now.Add(time.Second))
	if len(closed) != 1 || closed[0].DisconnectedAt == nil || closed[0].DisconnectReason != "worker exited" {
		t.Fatalf("closed sessions = %+v", closed)
	}
	if _, err := store.DeleteClient("partner-a"); err != nil {
		t.Fatalf("delete after worker cleanup: %v", err)
	}
}

func TestRotatePublishRelayKeyReturnsNewPassphrase(t *testing.T) {
	store := testStore(t)
	created, err := store.UpsertRelay(Relay{
		ID: "publish-srt", Direction: DirectionPublish,
		InputURL: "udp://239.1.1.10:1234", DestinationAddress: "203.0.113.50",
		DestinationPort: 9000, StreamID: "channel-1",
	})
	if err != nil {
		t.Fatal(err)
	}
	rotated, err := store.RotateRelayKey("publish-srt")
	if err != nil {
		t.Fatal(err)
	}
	if rotated.Passphrase == "" || rotated.Passphrase == created.Passphrase || rotated.Config.KeyVersion != created.Config.KeyVersion+1 {
		t.Fatalf("rotated relay = %+v created=%+v", rotated, created)
	}
	if _, err := store.RotateRelayKey("news-srt"); err == nil {
		t.Fatal("listener relay key rotation unexpectedly succeeded")
	}
}

func TestStoreRejectsCorruptStateAndMasterKey(t *testing.T) {
	dir := t.TempDir()
	statePath := filepath.Join(dir, "state.json")
	keyPath := filepath.Join(dir, "master.key")
	auditDir := filepath.Join(dir, "audit")
	if err := os.WriteFile(statePath, []byte("{not-json"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := NewStore(statePath, keyPath, auditDir, 30); err == nil {
		t.Fatal("expected corrupt state error")
	}
	if err := os.Remove(statePath); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(keyPath, []byte("not-a-valid-master-key\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := NewStore(statePath, keyPath, auditDir, 30); err == nil {
		t.Fatal("expected corrupt master key error")
	}
}

func TestRelayRejectsInvalidInputTimeout(t *testing.T) {
	store := testStore(t)
	_, err := store.UpsertRelay(Relay{
		ID: "bad-timeout", InputURL: "udp://239.1.1.10:1234",
		BindAddress: "0.0.0.0", Port: 9000, InputTimeoutSeconds: 2,
	})
	if err == nil {
		t.Fatal("expected input timeout validation error")
	}
}

func TestInputStallChangesRuntimeStateAndAuditsTransitions(t *testing.T) {
	store := testStore(t)
	_, err := store.UpsertRelay(Relay{
		ID: "news-hd", InputURL: "udp://239.1.1.10:1234",
		BindAddress: "0.0.0.0", Port: 9000,
	})
	if err != nil {
		t.Fatal(err)
	}
	store.ApplyWorkerEvent("news-hd", WorkerEvent{Type: "relay_ready"})
	store.ApplyWorkerEvent("news-hd", WorkerEvent{Type: "relay_metrics", Reason: "multicast input has no packets for 10 seconds"})
	view, _ := store.GetRelay("news-hd")
	if view.State.Status != "degraded" || view.State.LastError == "" {
		t.Fatalf("degraded state = %+v", view.State)
	}
	store.ApplyWorkerEvent("news-hd", WorkerEvent{Type: "relay_metrics", Reason: "multicast input has no packets for 10 seconds"})
	store.ApplyWorkerEvent("news-hd", WorkerEvent{Type: "relay_metrics"})
	events, err := store.Audit(AuditFilter{RelayID: "news-hd", Limit: 20})
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 2 || events[0].Type != "input_restored" || events[1].Type != "input_stalled" {
		t.Fatalf("input transition audit = %+v", events)
	}
}

func TestRelayRejectsUnicastInput(t *testing.T) {
	store := testStore(t)
	_, err := store.UpsertRelay(Relay{
		ID:          "bad-relay",
		InputURL:    "udp://192.0.2.10:1234",
		BindAddress: "0.0.0.0",
		Port:        9000,
	})
	if err == nil {
		t.Fatal("expected unicast input validation error")
	}
}

func TestRelayRejectsRTPUntilHeaderParsingIsSupported(t *testing.T) {
	store := testStore(t)
	_, err := store.UpsertRelay(Relay{
		ID:          "rtp-relay",
		InputURL:    "rtp://239.1.1.10:1234",
		BindAddress: "0.0.0.0",
		Port:        9000,
	})
	if err == nil {
		t.Fatal("expected unsupported RTP input validation error")
	}
}

func TestAuditIsSeparateAndFilterable(t *testing.T) {
	store := testStore(t)
	_, err := store.RecordAudit(AuditEvent{
		Type:     "connection_rejected",
		Level:    "warning",
		RelayID:  "news-hd",
		ClientID: "partner-a",
		RemoteIP: "203.0.113.11",
		Reason:   "IP is not allowed",
	})
	if err != nil {
		t.Fatal(err)
	}
	events, err := store.Audit(AuditFilter{ClientID: "partner-a", Limit: 20})
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 1 || events[0].Reason != "IP is not allowed" || events[0].ID == "" {
		t.Fatalf("audit events = %+v", events)
	}
}

func testStore(t *testing.T) *Store {
	t.Helper()
	dir := t.TempDir()
	store, err := NewStore(
		filepath.Join(dir, "state.json"),
		filepath.Join(dir, "master.key"),
		filepath.Join(dir, "audit"),
		30,
	)
	if err != nil {
		t.Fatal(err)
	}
	return store
}

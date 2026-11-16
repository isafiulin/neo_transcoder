package accounts

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"neotranscoder/internal/auth"
)

func TestLegacyStatePreservesAccountsAndEncoderData(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state.json")
	store, err := NewStore(path)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = store.ChangePassword("admin", "123456", "existing-password", true); err != nil {
		t.Fatal(err)
	}
	secret := store.AuthSecret()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var legacy map[string]json.RawMessage
	if err = json.Unmarshal(data, &legacy); err != nil {
		t.Fatal(err)
	}
	legacy["streams"] = json.RawMessage(`[{"id":"old","profile_name":"retired-profile"}]`)
	legacy["profiles"] = json.RawMessage(`[{"name":"retired-profile","unknown_option":true}]`)
	data, err = json.Marshal(legacy)
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(path, data, 0600); err != nil {
		t.Fatal(err)
	}
	store, err = NewStore(path)
	if err != nil {
		t.Fatal(err)
	}
	user, ok := store.Authenticate("admin", "existing-password")
	if !ok || user.MustChangePassword || store.AuthSecret() != secret {
		t.Fatal("existing credentials changed")
	}
	if _, err = store.CreateUser("operator", "operator-password"); err != nil {
		t.Fatal(err)
	}
	reopened, err := NewStore(path)
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := reopened.Authenticate("operator", "operator-password"); !ok {
		t.Fatal("account not persisted")
	}
	for key, want := range map[string]json.RawMessage{"streams": legacy["streams"], "profiles": legacy["profiles"]} {
		data, err = os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		var saved map[string]json.RawMessage
		if err = json.Unmarshal(data, &saved); err != nil {
			t.Fatal(err)
		}
		var gotValue, wantValue any
		if err = json.Unmarshal(saved[key], &gotValue); err != nil {
			t.Fatal(err)
		}
		if err = json.Unmarshal(want, &wantValue); err != nil {
			t.Fatal(err)
		}
		got, _ := json.Marshal(gotValue)
		expected, _ := json.Marshal(wantValue)
		if string(got) != string(expected) {
			t.Fatalf("legacy %s changed", key)
		}
	}
	claims := auth.Claims{Subject: user.Username, TokenVersion: user.TokenVersion}
	if _, err = reopened.ChangePassword("admin", "existing-password", "new-password", true); err != nil {
		t.Fatal(err)
	}
	if _, ok = reopened.VerifyTokenClaims(claims); ok {
		t.Fatal("old token still valid")
	}
}

func TestFailedAccountWriteKeepsCredentials(t *testing.T) {
	store, err := NewStore("")
	if err != nil {
		t.Fatal(err)
	}
	if _, err = store.CreateUser("operator", "old-password"); err != nil {
		t.Fatal(err)
	}
	blocker := filepath.Join(t.TempDir(), "file")
	if err = os.WriteFile(blocker, []byte("x"), 0600); err != nil {
		t.Fatal(err)
	}
	store.path = filepath.Join(blocker, "state.json")
	if _, err = store.ChangePassword("operator", "old-password", "new-password", true); err == nil {
		t.Fatal("expected write failure")
	}
	if _, ok := store.Authenticate("operator", "old-password"); !ok {
		t.Fatal("password changed on failure")
	}
	if _, err = store.DeleteUser("operator"); err == nil {
		t.Fatal("expected write failure")
	}
	if _, ok := store.GetUser("operator"); !ok {
		t.Fatal("user removed on failure")
	}
	if _, err = store.CreateUser("another", "new-password"); err == nil {
		t.Fatal("expected write failure")
	}
	if _, ok := store.GetUser("another"); ok {
		t.Fatal("user created on failure")
	}
}

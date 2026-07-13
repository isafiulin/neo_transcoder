package auth

import (
	"strings"
	"testing"
	"time"
)

func TestPasswordAndTokenRoundTrip(t *testing.T) {
	hash, err := HashPassword("123456")
	if err != nil {
		t.Fatal(err)
	}
	if !VerifyPassword(hash, "123456") {
		t.Fatal("expected password to verify")
	}
	if VerifyPassword(hash, "wrong") {
		t.Fatal("wrong password verified")
	}

	secret, err := GenerateSecret()
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	token, err := IssueToken(secret, Claims{
		Subject:      "admin",
		Type:         "access",
		TokenVersion: 1,
		ExpiresAt:    now.Add(time.Minute),
	})
	if err != nil {
		t.Fatal(err)
	}
	claims, err := VerifyToken(secret, token, "access", now)
	if err != nil {
		t.Fatal(err)
	}
	if claims.Subject != "admin" || claims.TokenVersion != 1 {
		t.Fatalf("unexpected claims: %#v", claims)
	}
	if _, err := VerifyToken(secret, token, "access", now.Add(2*time.Minute)); err == nil {
		t.Fatal("expired token verified")
	}
}

func TestTokenRejectsTamperingMalformedClaimsAndWrongSecret(t *testing.T) {
	now := time.Now()
	secret, err := GenerateSecret()
	if err != nil {
		t.Fatal(err)
	}
	valid, err := IssueToken(secret, Claims{
		Subject: "admin", Type: "access", TokenVersion: 1, ExpiresAt: now.Add(time.Minute),
	})
	if err != nil {
		t.Fatal(err)
	}
	tests := []struct {
		name   string
		secret string
		token  string
		kind   string
	}{
		{name: "missing signature", secret: secret, token: "payload", kind: "access"},
		{name: "wrong secret", secret: "different", token: valid, kind: "access"},
		{name: "wrong type", secret: secret, token: valid, kind: "refresh"},
		{name: "tampered signature", secret: secret, token: valid[:len(valid)-1] + "x", kind: "access"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if _, err := VerifyToken(test.secret, test.token, test.kind, now); err == nil {
				t.Fatal("expected token rejection")
			}
		})
	}

	invalidClaims, err := IssueToken(secret, Claims{Type: "access", ExpiresAt: now.Add(time.Minute)})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := VerifyToken(secret, invalidClaims, "access", now); err == nil {
		t.Fatal("token without subject/version was accepted")
	}
	if VerifyPassword("invalid-hash", "password") || VerifyPassword(strings.Repeat("$", 4), "password") {
		t.Fatal("malformed password hash was accepted")
	}
}

func TestUserValidationRejectsUnsafeCredentials(t *testing.T) {
	for _, username := range []string{"ab", strings.Repeat("a", 65), "admin user", "админ"} {
		if err := ValidateUsername(username); err == nil {
			t.Fatalf("username %q was accepted", username)
		}
	}
	if err := ValidatePassword("12345"); err == nil {
		t.Fatal("short password was accepted")
	}
}

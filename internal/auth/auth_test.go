package auth

import (
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

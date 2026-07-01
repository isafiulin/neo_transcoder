package auth

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"hash"
	"strconv"
	"strings"
	"time"
)

const (
	AccessTokenTTL  = 15 * time.Minute
	RefreshTokenTTL = 7 * 24 * time.Hour
)

type User struct {
	Username           string    `json:"username"`
	PasswordHash       string    `json:"password_hash"`
	MustChangePassword bool      `json:"must_change_password"`
	CreatedAt          time.Time `json:"created_at"`
	UpdatedAt          time.Time `json:"updated_at"`
	TokenVersion       int       `json:"token_version"`
}

type PublicUser struct {
	Username           string    `json:"username"`
	MustChangePassword bool      `json:"must_change_password"`
	CreatedAt          time.Time `json:"created_at"`
	UpdatedAt          time.Time `json:"updated_at"`
}

type Claims struct {
	Subject      string    `json:"sub"`
	Type         string    `json:"typ"`
	TokenVersion int       `json:"ver"`
	ExpiresAt    time.Time `json:"exp"`
}

func NewUser(username, password string, mustChange bool, now time.Time) (User, error) {
	if err := ValidateUsername(username); err != nil {
		return User{}, err
	}
	if err := ValidatePassword(password); err != nil {
		return User{}, err
	}
	hash, err := HashPassword(password)
	if err != nil {
		return User{}, err
	}
	return User{
		Username:           username,
		PasswordHash:       hash,
		MustChangePassword: mustChange,
		CreatedAt:          now,
		UpdatedAt:          now,
		TokenVersion:       1,
	}, nil
}

func Public(user User) PublicUser {
	return PublicUser{
		Username:           user.Username,
		MustChangePassword: user.MustChangePassword,
		CreatedAt:          user.CreatedAt,
		UpdatedAt:          user.UpdatedAt,
	}
}

func ValidateUsername(username string) error {
	if len(username) < 3 || len(username) > 64 {
		return fmt.Errorf("username must be 3-64 characters")
	}
	for _, r := range username {
		if r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '_' || r == '-' || r == '.' {
			continue
		}
		return fmt.Errorf("username contains invalid characters")
	}
	return nil
}

func ValidatePassword(password string) error {
	if len(password) < 6 {
		return fmt.Errorf("password must be at least 6 characters")
	}
	return nil
}

func GenerateSecret() (string, error) {
	data := make([]byte, 32)
	if _, err := rand.Read(data); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(data), nil
}

func HashPassword(password string) (string, error) {
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	key := pbkdf2Key([]byte(password), salt, 120000, 32, sha256.New)
	return "pbkdf2-sha256$120000$" + base64.RawURLEncoding.EncodeToString(salt) + "$" + base64.RawURLEncoding.EncodeToString(key), nil
}

func VerifyPassword(hashValue, password string) bool {
	parts := strings.Split(hashValue, "$")
	if len(parts) != 4 || parts[0] != "pbkdf2-sha256" {
		return false
	}
	iterations, err := strconv.Atoi(parts[1])
	if err != nil || iterations < 1 {
		return false
	}
	salt, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		return false
	}
	expected, err := base64.RawURLEncoding.DecodeString(parts[3])
	if err != nil {
		return false
	}
	actual := pbkdf2Key([]byte(password), salt, iterations, len(expected), sha256.New)
	return subtle.ConstantTimeCompare(actual, expected) == 1
}

func IssueToken(secret string, claims Claims) (string, error) {
	body, err := json.Marshal(claims)
	if err != nil {
		return "", err
	}
	payload := base64.RawURLEncoding.EncodeToString(body)
	signature := sign(secret, payload)
	return payload + "." + signature, nil
}

func VerifyToken(secret, token, kind string, now time.Time) (Claims, error) {
	payload, signature, ok := strings.Cut(token, ".")
	if !ok || payload == "" || signature == "" {
		return Claims{}, fmt.Errorf("invalid token")
	}
	if subtle.ConstantTimeCompare([]byte(sign(secret, payload)), []byte(signature)) != 1 {
		return Claims{}, fmt.Errorf("invalid token")
	}
	data, err := base64.RawURLEncoding.DecodeString(payload)
	if err != nil {
		return Claims{}, fmt.Errorf("invalid token")
	}
	var claims Claims
	if err := json.Unmarshal(data, &claims); err != nil {
		return Claims{}, fmt.Errorf("invalid token")
	}
	if claims.Type != kind {
		return Claims{}, fmt.Errorf("invalid token type")
	}
	if !claims.ExpiresAt.After(now) {
		return Claims{}, fmt.Errorf("token expired")
	}
	if claims.Subject == "" || claims.TokenVersion < 1 {
		return Claims{}, fmt.Errorf("invalid token")
	}
	return claims, nil
}

func sign(secret, payload string) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(payload))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func pbkdf2Key(password, salt []byte, iter, keyLen int, h func() hash.Hash) []byte {
	prf := hmac.New(h, password)
	hashLen := prf.Size()
	numBlocks := (keyLen + hashLen - 1) / hashLen
	var buf [4]byte
	dk := make([]byte, 0, numBlocks*hashLen)
	u := make([]byte, hashLen)
	for block := 1; block <= numBlocks; block++ {
		prf.Reset()
		prf.Write(salt)
		binary.BigEndian.PutUint32(buf[:], uint32(block))
		prf.Write(buf[:])
		sum := prf.Sum(nil)
		copy(u, sum)
		for i := 1; i < iter; i++ {
			prf.Reset()
			prf.Write(u)
			u = prf.Sum(u[:0])
			for x := 0; x < hashLen; x++ {
				sum[x] ^= u[x]
			}
		}
		dk = append(dk, sum...)
	}
	return dk[:keyLen]
}

package config

import "testing"

func TestDefaultConfigIsValid(t *testing.T) {
	if err := Default().Validate(); err != nil {
		t.Fatal(err)
	}
}

func TestConfigRejectsInvalidPort(t *testing.T) {
	cfg := Default()
	cfg.Server.Port = 70000
	if err := cfg.Validate(); err == nil {
		t.Fatal("expected invalid port error")
	}
}

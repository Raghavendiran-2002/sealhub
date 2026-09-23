package auth

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/raghavendiran/sealhub/pkg/client"
)

type credFile struct {
	AccessToken string `json:"access_token"`
	Server      string `json:"server"`
}

func credPath() (string, error) {
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "hub", "credentials.json"), nil
}

func SaveToken(server, token string) error {
	p, err := credPath()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(p), 0o700); err != nil {
		return err
	}
	b, err := json.Marshal(credFile{AccessToken: token, Server: server})
	if err != nil {
		return err
	}
	return os.WriteFile(p, b, 0o600)
}

func LoadToken() (string, error) {
	p, err := credPath()
	if err != nil {
		return "", err
	}
	b, err := os.ReadFile(p)
	if err != nil {
		return "", err
	}
	var c credFile
	if err := json.Unmarshal(b, &c); err != nil {
		return "", err
	}
	return c.AccessToken, nil
}

func Logout() error {
	p, err := credPath()
	if err != nil {
		return err
	}
	return os.Remove(p)
}

// Login exchanges SEALHUB_ID_TOKEN with hubd for an API JWT.
func Login(server string) error {
	idTok := os.Getenv("SEALHUB_ID_TOKEN")
	issuer := os.Getenv("SEALHUB_OIDC_ISSUER")
	if idTok == "" || issuer == "" {
		return fmt.Errorf("set SEALHUB_ID_TOKEN and SEALHUB_OIDC_ISSUER (issuer name from system/issuers.yaml)")
	}
	c := client.New(server, "")
	access, err := c.ExchangeIDToken(context.Background(), issuer, idTok)
	if err != nil {
		return err
	}
	return SaveToken(server, access)
}

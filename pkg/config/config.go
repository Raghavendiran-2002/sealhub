package config

import (
	"fmt"
	"os"
	"time"

	"gopkg.in/yaml.v3"
)

// Config is hubd configuration.
type Config struct {
	Server     ServerConfig     `yaml:"server"`
	GitHub     GitHubConfig     `yaml:"github"`
	Git        GitConfig        `yaml:"git"`
	Encryption EncryptionConfig `yaml:"encryption"`
	Auth       AuthConfig       `yaml:"auth"`
	Freshness  FreshnessConfig  `yaml:"freshness"`
}

type ServerConfig struct {
	Listen      string `yaml:"listen"`
	ExternalURL string `yaml:"externalURL"`
}

type GitHubConfig struct {
	Owner  string         `yaml:"owner"`
	Repo   string         `yaml:"repo"`
	Branch string         `yaml:"branch"`
	Auth   GitHubAuth     `yaml:"auth"`
}

type GitHubAuth struct {
	PATFile string `yaml:"patFile"`
}

type GitConfig struct {
	LocalPath string `yaml:"localPath"`
}

type EncryptionConfig struct {
	KeyringFile string `yaml:"keyringFile"`
}

type AuthConfig struct {
	BootstrapToken string `yaml:"bootstrapToken"`
	JWTSecretFile  string `yaml:"jwtSecretFile"`
}

type FreshnessConfig struct {
	PollInterval string `yaml:"pollInterval"`
}

func Load(path string) (*Config, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var c Config
	if err := yaml.Unmarshal(raw, &c); err != nil {
		return nil, err
	}
	c.applyDefaults()
	if err := c.validate(); err != nil {
		return nil, err
	}
	return &c, nil
}

func (c *Config) applyDefaults() {
	if c.Server.Listen == "" {
		c.Server.Listen = ":8080"
	}
	if c.GitHub.Branch == "" {
		c.GitHub.Branch = "main"
	}
	if c.Freshness.PollInterval == "" {
		c.Freshness.PollInterval = "15s"
	}
	if c.Auth.JWTSecretFile == "" {
		c.Auth.JWTSecretFile = ""
	}
	if tok := os.Getenv("SEALHUB_BOOTSTRAP_TOKEN"); tok != "" && c.Auth.BootstrapToken == "" {
		c.Auth.BootstrapToken = tok
	}
}

func (c *Config) validate() error {
	if c.Server.ExternalURL == "" {
		return fmt.Errorf("server.externalURL is required")
	}
	if c.GitHub.Owner == "" || c.GitHub.Repo == "" {
		return fmt.Errorf("github.owner and github.repo are required")
	}
	if c.GitHub.Auth.PATFile == "" {
		return fmt.Errorf("github.auth.patFile is required")
	}
	if c.Git.LocalPath == "" {
		return fmt.Errorf("git.localPath is required")
	}
	if c.Encryption.KeyringFile == "" {
		return fmt.Errorf("encryption.keyringFile is required")
	}
	return nil
}

func (c *Config) PollDuration() time.Duration {
	d, err := time.ParseDuration(c.Freshness.PollInterval)
	if err != nil {
		return 15 * time.Second
	}
	return d
}

func (c *Config) CloneURL() string {
	return fmt.Sprintf("https://github.com/%s/%s.git", c.GitHub.Owner, c.GitHub.Repo)
}

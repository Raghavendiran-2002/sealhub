package pocket

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/raghavendiran/sealhub/pkg/client"
)

// Options configure pocket backup/restore.
type Options struct {
	Home      string // directory with docker-compose.yaml and .env
	Instance  string // homelab segment in API paths
	StopCompose bool
}

func DefaultHome() string {
	if v := os.Getenv("POCKET_ID_HOME"); v != "" {
		return v
	}
	return "/Users/raghavendiran/Desktop/Home-Lab/Pocket_ID_Mac/pocket-id"
}

func (o Options) normalize() Options {
	if o.Home == "" {
		o.Home = DefaultHome()
	}
	o.Home = filepath.Clean(o.Home)
	if o.Instance == "" {
		o.Instance = "homelab"
	}
	return o
}

func dataDir(home string) string {
	return filepath.Join(home, "data")
}

func envFile(home string) string {
	return filepath.Join(home, ".env")
}

// Backup uploads Pocket ID .env (secrets/) and SQLite DB (pocket/).
func Backup(ctx context.Context, c *client.Client, opt Options) error {
	opt = opt.normalize()
	home := opt.Home
	envPath := envFile(home)
	envBytes, err := os.ReadFile(envPath)
	if err != nil {
		return fmt.Errorf("read .env: %w", err)
	}

	if opt.StopCompose {
		if err := stopPocketID(ctx, home); err != nil {
			return err
		}
		defer func() { _ = startPocketID(context.Background(), home) }()
	}

	tmpDB, err := os.CreateTemp("", "pocket-id-*.db")
	if err != nil {
		return err
	}
	tmpPath := tmpDB.Name()
	_ = tmpDB.Close()
	defer os.Remove(tmpPath)

	srcDB := filepath.Join(dataDir(home), "pocket-id.db")
	srcInfo, _ := os.Stat(srcDB)
	rawCopy := opt.StopCompose
	if err := snapshotDatabase(dataDir(home), tmpPath, rawCopy); err != nil {
		return err
	}
	dbBytes, err := os.ReadFile(tmpPath)
	if err != nil {
		return err
	}
	if srcInfo != nil {
		fmt.Fprintf(os.Stderr, "pocket backup: source %s (%d bytes on disk, rawCopy=%v)\n", srcDB, srcInfo.Size(), rawCopy)
	}

	doc, err := encodeBackup(dbBytes, home)
	if err != nil {
		return err
	}

	ct := "application/yaml"
	falseEnc := false
	if _, err := c.Apply(ctx, EnvDocumentPath(opt.Instance), client.ApplyRequest{
		Document:    string(envBytes),
		ContentType: "text/plain",
	}); err != nil {
		return fmt.Errorf("apply env: %w", err)
	}
	if _, err := c.Apply(ctx, DBDocumentPath(opt.Instance), client.ApplyRequest{
		Document:    doc,
		ContentType: ct,
		Encrypt:     &falseEnc,
	}); err != nil {
		return fmt.Errorf("apply database: %w", err)
	}

	fmt.Fprintf(os.Stderr, "pocket backup: secrets/%s/pocket-id.env (%d bytes)\n", opt.Instance, len(envBytes))
	fmt.Fprintf(os.Stderr, "pocket backup: pocket/%s/pocket-id.db.yaml (%d bytes db, sha in doc)\n", opt.Instance, len(dbBytes))
	return nil
}

// Restore downloads from SealHub and writes .env + pocket-id.db under Home.
func Restore(ctx context.Context, c *client.Client, opt Options) error {
	opt = opt.normalize()
	home := opt.Home

	envEnv, err := c.Get(ctx, EnvDocumentPath(opt.Instance))
	if err != nil {
		return fmt.Errorf("get env: %w", err)
	}
	dbEnv, err := c.Get(ctx, DBDocumentPath(opt.Instance))
	if err != nil {
		return fmt.Errorf("get database: %w", err)
	}
	dbBytes, err := decodeBackup(dbEnv.Document)
	if err != nil {
		return err
	}

	if opt.StopCompose {
		if err := stopPocketID(ctx, home); err != nil {
			return err
		}
		defer func() { _ = startPocketID(context.Background(), home) }()
	}

	if err := os.MkdirAll(dataDir(home), 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(envFile(home), []byte(strings.TrimSpace(envEnv.Document)+"\n"), 0o600); err != nil {
		return fmt.Errorf("write .env: %w", err)
	}

	dbPath := filepath.Join(dataDir(home), "pocket-id.db")
	for _, suffix := range []string{"-shm", "-wal"} {
		_ = os.Remove(dbPath + suffix)
	}
	if err := os.WriteFile(dbPath, dbBytes, 0o600); err != nil {
		return fmt.Errorf("write database: %w", err)
	}

	fmt.Fprintf(os.Stderr, "pocket restore: wrote %s and %s (%d bytes db)\n", envFile(home), dbPath, len(dbBytes))
	return nil
}

// ClientWithTimeout returns a copy of the client with a longer HTTP timeout for large backups.
func ClientWithTimeout(c *client.Client, d time.Duration) *client.Client {
	if c == nil {
		return c
	}
	cp := *c
	if cp.HTTPClient != nil {
		hc := *cp.HTTPClient
		hc.Timeout = d
		cp.HTTPClient = &hc
	}
	return &cp
}

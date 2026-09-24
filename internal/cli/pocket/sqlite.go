package pocket

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

// snapshotDatabase copies pocket-id.db to destPath.
// When rawCopy is true (service stopped), the on-disk file is copied byte-for-byte so
// restored size matches the source. When false, sqlite3 .backup yields a compact logical copy.
func snapshotDatabase(dataDir, destPath string, rawCopy bool) error {
	src := filepath.Join(dataDir, "pocket-id.db")
	if _, err := os.Stat(src); err != nil {
		return fmt.Errorf("database %s: %w", src, err)
	}
	if rawCopy {
		in, err := os.ReadFile(src)
		if err != nil {
			return err
		}
		return os.WriteFile(destPath, in, 0o600)
	}
	if _, err := exec.LookPath("sqlite3"); err == nil {
		ctx := context.Background()
		cmd := exec.CommandContext(ctx, "sqlite3", src, fmt.Sprintf(".backup '%s'", destPath))
		if out, err := cmd.CombinedOutput(); err != nil {
			return fmt.Errorf("sqlite3 backup: %s: %w", stringsTrim(string(out)), err)
		}
		return nil
	}
	in, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	return os.WriteFile(destPath, in, 0o600)
}

func stringsTrim(s string) string {
	if len(s) > 512 {
		return s[:512] + "..."
	}
	return s
}

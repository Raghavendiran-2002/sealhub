package crypto

import (
	"encoding/base64"
	"os"
	"path/filepath"
	"testing"
)

func TestEncryptRoundTrip(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "keyring")
	key := make([]byte, 32)
	for i := range key {
		key[i] = byte(i)
	}
	line := base64.StdEncoding.EncodeToString(key) + "\n"
	if err := os.WriteFile(path, []byte(line), 0o600); err != nil {
		t.Fatal(err)
	}
	kr, err := LoadKeyRing(path)
	if err != nil {
		t.Fatal(err)
	}
	ct, err := kr.Encrypt([]byte("hello"))
	if err != nil {
		t.Fatal(err)
	}
	pt, err := kr.Decrypt(ct)
	if err != nil {
		t.Fatal(err)
	}
	if string(pt) != "hello" {
		t.Fatalf("got %q", pt)
	}
}

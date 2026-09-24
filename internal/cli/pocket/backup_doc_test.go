package pocket

import (
	"bytes"
	"testing"
)

func TestEncodeDecodeBackup(t *testing.T) {
	raw := []byte("sqlite-bytes-demo")
	doc, err := encodeBackup(raw, "/tmp/pocket-id")
	if err != nil {
		t.Fatal(err)
	}
	out, err := decodeBackup(doc)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(raw, out) {
		t.Fatalf("round-trip mismatch")
	}
}

func TestDecodeBackupBadSHA(t *testing.T) {
	doc, _ := encodeBackup([]byte("x"), "")
	doc = string(bytes.ReplaceAll([]byte(doc), []byte("sha256: "), []byte("sha256: 0000000000000000000000000000000000000000000000000000000000000000")))
	_, err := decodeBackup(doc)
	if err == nil {
		t.Fatal("expected sha error")
	}
}

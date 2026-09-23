package crypto

import (
	"bufio"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"io"
	"os"
	"strings"
)

// KeyRing holds encryption keys; first key encrypts, all keys decrypt.
type KeyRing struct {
	keys [][]byte
}

// LoadKeyRing reads newline-delimited base64 32-byte keys.
func LoadKeyRing(path string) (*KeyRing, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var keys [][]byte
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		k, err := base64.StdEncoding.DecodeString(line)
		if err != nil {
			return nil, fmt.Errorf("keyring: invalid base64: %w", err)
		}
		if len(k) != 32 {
			return nil, fmt.Errorf("keyring: key must be 32 bytes, got %d", len(k))
		}
		keys = append(keys, k)
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}
	if len(keys) == 0 {
		return nil, fmt.Errorf("keyring: no keys")
	}
	return &KeyRing{keys: keys}, nil
}

// Encrypt returns base64(nonce||ciphertext).
func (kr *KeyRing) Encrypt(plaintext []byte) (string, error) {
	key := kr.keys[0]
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", err
	}
	out := gcm.Seal(nonce, nonce, plaintext, nil)
	return base64.StdEncoding.EncodeToString(out), nil
}

// Decrypt decodes base64(nonce||ciphertext).
func (kr *KeyRing) Decrypt(encoded string) ([]byte, error) {
	raw, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return nil, err
	}
	var lastErr error
	for _, key := range kr.keys {
		plain, err := decryptWithKey(key, raw)
		if err == nil {
			return plain, nil
		}
		lastErr = err
	}
	if lastErr != nil {
		return nil, lastErr
	}
	return nil, fmt.Errorf("decrypt failed")
}

func decryptWithKey(key, raw []byte) ([]byte, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	ns := gcm.NonceSize()
	if len(raw) < ns {
		return nil, fmt.Errorf("ciphertext too short")
	}
	return gcm.Open(nil, raw[:ns], raw[ns:], nil)
}

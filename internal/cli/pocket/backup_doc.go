package pocket

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

type backupDoc struct {
	APIVersion string         `yaml:"apiVersion"`
	Kind       string         `yaml:"kind"`
	Metadata   backupMeta     `yaml:"metadata"`
	Spec       backupSpec     `yaml:"spec"`
	Data       string         `yaml:"data"`
}

type backupMeta struct {
	CreatedAt string `yaml:"createdAt"`
	Source    string `yaml:"source,omitempty"`
	SHA256    string `yaml:"sha256"`
}

type backupSpec struct {
	Encoding     string `yaml:"encoding"`
	SizeBytes    int    `yaml:"sizeBytes"`
	DatabaseFile string `yaml:"databaseFile"`
}

func encodeBackup(db []byte, source string) (string, error) {
	sum := sha256.Sum256(db)
	doc := backupDoc{
		APIVersion: BackupAPI,
		Kind:       BackupKind,
		Metadata: backupMeta{
			CreatedAt: time.Now().UTC().Format(time.RFC3339),
			Source:    source,
			SHA256:    hex.EncodeToString(sum[:]),
		},
		Spec: backupSpec{
			Encoding:     "base64",
			SizeBytes:    len(db),
			DatabaseFile: "pocket-id.db",
		},
		Data: base64.StdEncoding.EncodeToString(db),
	}
	out, err := yaml.Marshal(doc)
	if err != nil {
		return "", err
	}
	return string(out), nil
}

func decodeBackup(document string) ([]byte, error) {
	var doc backupDoc
	if err := yaml.Unmarshal([]byte(document), &doc); err != nil {
		return nil, err
	}
	if doc.Kind != BackupKind {
		return nil, fmt.Errorf("unexpected kind %q", doc.Kind)
	}
	if doc.Spec.Encoding != "base64" {
		return nil, fmt.Errorf("unsupported encoding %q", doc.Spec.Encoding)
	}
	raw, err := base64.StdEncoding.DecodeString(strings.TrimSpace(doc.Data))
	if err != nil {
		return nil, fmt.Errorf("decode base64: %w", err)
	}
	if doc.Metadata.SHA256 != "" {
		sum := sha256.Sum256(raw)
		if hex.EncodeToString(sum[:]) != doc.Metadata.SHA256 {
			return nil, fmt.Errorf("sha256 mismatch")
		}
	}
	return raw, nil
}

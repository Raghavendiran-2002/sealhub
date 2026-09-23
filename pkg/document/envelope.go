package document

import (
	"fmt"
	"strings"

	"gopkg.in/yaml.v3"
)

const SchemaVersion = 1

// Metadata holds document envelope metadata.
type Metadata struct {
	Version     int               `yaml:"version" json:"version"`
	ContentType string            `yaml:"contentType" json:"contentType"`
	Encrypted   bool              `yaml:"encrypted" json:"encrypted"`
	Labels      map[string]string `yaml:"labels,omitempty" json:"labels,omitempty"`
	Owner       string            `yaml:"owner,omitempty" json:"owner,omitempty"`
}

// Envelope is the on-disk YAML shape for data documents.
type Envelope struct {
	Schema   int      `yaml:"schema"`
	Metadata Metadata `yaml:"metadata"`
	Document string   `yaml:"document"`
}

// ParseEnvelope unmarshals envelope YAML.
func ParseEnvelope(raw []byte) (*Envelope, error) {
	var env Envelope
	if err := yaml.Unmarshal(raw, &env); err != nil {
		return nil, err
	}
	if env.Schema != 0 && env.Schema != SchemaVersion {
		return nil, fmt.Errorf("unsupported schema %d", env.Schema)
	}
	if env.Schema == 0 {
		env.Schema = SchemaVersion
	}
	return &env, nil
}

// Marshal serializes the envelope.
func (e *Envelope) Marshal() ([]byte, error) {
	e.Schema = SchemaVersion
	return yaml.Marshal(e)
}

// GitPath returns the path under the repo root for an API document key.
func GitPath(apiPath string) string {
	apiPath = strings.TrimPrefix(apiPath, "/")
	if strings.HasPrefix(apiPath, "system/") {
		return apiPath
	}
	return "data/" + apiPath
}

// DefaultEncryptForPath returns whether apply should encrypt by default.
func DefaultEncryptForPath(apiPath string) bool {
	apiPath = strings.TrimPrefix(apiPath, "/")
	return strings.HasPrefix(apiPath, "secrets/")
}

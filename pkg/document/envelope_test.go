package document

import "testing"

func TestGitPath(t *testing.T) {
	if GitPath("secrets/ns/a.yaml") != "data/secrets/ns/a.yaml" {
		t.Fatal(GitPath("secrets/ns/a.yaml"))
	}
}

func TestDefaultEncrypt(t *testing.T) {
	if !DefaultEncryptForPath("secrets/x.yaml") {
		t.Fatal()
	}
	if DefaultEncryptForPath("config/x.yaml") {
		t.Fatal()
	}
}

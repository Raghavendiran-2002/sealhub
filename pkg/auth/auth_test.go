package auth

import "testing"

func TestPathMatch(t *testing.T) {
	if !pathMatch("secrets/ns/a.yaml", "secrets/ns/**") {
		t.Fatal()
	}
	if pathMatch("secrets/other/a.yaml", "secrets/ns/**") {
		t.Fatal()
	}
}

func TestBootstrapAuthorize(t *testing.T) {
	e := NewEngine("bootstrap-secret", []byte("jwt"))
	p, err := e.AuthenticateBearer("bootstrap-secret")
	if err != nil {
		t.Fatal(err)
	}
	if !e.Authorize(p, "data/secrets/x.yaml", ActionWrite) {
		t.Fatal()
	}
}

package main

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"os"

	"github.com/raghavendiran/sealhub/pkg/auth"
	"github.com/raghavendiran/sealhub/pkg/client"
	"gopkg.in/yaml.v3"
)

func runTokenCreate(server, adminToken string, args []string) {
	id := ""
	var paths []string
	var actions []string
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--id":
			i++
			if i < len(args) {
				id = args[i]
			}
		case "--read":
			i++
			if i < len(args) {
				paths = append(paths, args[i])
				actions = appendUnique(actions, "read")
			}
		case "--write":
			i++
			if i < len(args) {
				paths = append(paths, args[i])
				actions = appendUnique(actions, "write")
			}
		}
	}
	if id == "" || len(paths) == 0 {
		fatal("usage: hub token create --id NAME --read data/secrets/ns/** [--write ...]")
	}
	plain, err := randomToken()
	if err != nil {
		fatal(err)
	}
	hash, err := auth.HashToken(plain)
	if err != nil {
		fatal(err)
	}
	rec := auth.TokenRecord{ID: id, Hash: hash}
	rec.Scopes.Paths = paths
	rec.Scopes.Actions = actions
	body, err := yaml.Marshal(auth.TokensFile{Tokens: []auth.TokenRecord{rec}})
	if err != nil {
		fatal(err)
	}
	c := client.New(server, adminToken)
	_, err = c.Apply(context.Background(), "system/tokens.yaml", client.ApplyRequest{
		Document:    string(body),
		ContentType: "application/yaml",
	})
	if err != nil {
		fatal(err)
	}
	fmt.Fprintf(os.Stdout, "token_id=%s\nplaintext=%s\n", id, plain)
}

func randomToken() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return "hub_" + base64.RawURLEncoding.EncodeToString(b), nil
}

func appendUnique(slice []string, v string) []string {
	for _, s := range slice {
		if s == v {
			return slice
		}
	}
	return append(slice, v)
}

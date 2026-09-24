package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/raghavendiran/sealhub/pkg/changes"
	"github.com/raghavendiran/sealhub/pkg/client"
	"github.com/raghavendiran/sealhub/pkg/document"
	hubauth "github.com/raghavendiran/sealhub/internal/cli/auth"
)

func main() {
	server := flag.String("server", envOr("SEALHUB_SERVER", "http://localhost:8080"), "SealHub API URL")
	token := flag.String("token", envOr("SEALHUB_TOKEN", envOr("HUB_TOKEN", "")), "API token")
	output := flag.String("o", "yaml", "output format: yaml|json")
	flag.Parse()
	args := flag.Args()
	if len(args) == 0 {
		usage()
		os.Exit(2)
	}
	c := client.New(*server, resolveToken(*token))
	ctx := context.Background()

	switch args[0] {
	case "get":
		if len(args) < 2 {
			fatal("usage: hub get <path>")
		}
		env, err := c.Get(ctx, args[1])
		if err != nil {
			fatal(err)
		}
		printEnv(env, *output)
	case "list":
		prefix := ""
		if len(args) > 1 {
			prefix = args[1]
		}
		docs, err := c.List(ctx, prefix)
		if err != nil {
			fatal(err)
		}
		printJSON(docs, *output)
	case "apply":
		if len(args) < 2 {
			fatal("usage: hub apply <path> -f file")
		}
		path := args[1]
		body := readApplyBody(os.Args[1:])
		enc := document.DefaultEncryptForPath(path)
		env, err := c.Apply(ctx, path, client.ApplyRequest{Document: body, Encrypt: &enc})
		if err != nil {
			fatal(err)
		}
		printEnv(env, *output)
	case "delete":
		if len(args) < 2 {
			fatal("usage: hub delete <path>")
		}
		if err := c.Delete(ctx, args[1], 0); err != nil {
			fatal(err)
		}
	case "watch":
		prefix := ""
		if len(args) > 1 {
			prefix = args[1]
		}
		err := c.Watch(ctx, 0, prefix, func(ev changes.Event) error {
			b, _ := json.Marshal(ev)
			fmt.Println(string(b))
			return nil
		})
		if err != nil {
			fatal(err)
		}
	case "auth":
		if len(args) < 2 {
			fatal("usage: hub auth login|logout|whoami")
		}
		switch args[1] {
		case "login":
			if err := hubauth.Login(*server); err != nil {
				fatal(err)
			}
		case "logout":
			if err := hubauth.Logout(); err != nil {
				fatal(err)
			}
		case "whoami":
			tok, err := hubauth.LoadToken()
			if err != nil || tok == "" {
				fatal("not logged in")
			}
			fmt.Println("credentials present")
		default:
			fatal("unknown auth subcommand")
		}
	case "token":
		if len(args) < 2 {
			fatal("usage: hub token create ...")
		}
		if args[1] == "create" {
			runTokenCreate(*server, resolveToken(*token), args[2:])
		} else {
			fatal("usage: hub token create --id NAME --read path")
		}
	case "pocket":
		if len(args) < 2 {
			fatal("usage: hub pocket backup|restore")
		}
		runPocket(*server, resolveToken(*token), args[1:])
	default:
		usage()
		os.Exit(2)
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, `SealHub CLI

Usage:
  hub get <path>
  hub list [prefix]
  hub apply <path> [-f file]
  hub delete <path>
  hub watch [prefix]
  hub auth login|logout|whoami
  hub pocket backup|restore [-dir DIR] [-instance homelab] [-no-stop]

Environment:
  SEALHUB_SERVER, SEALHUB_TOKEN or HUB_TOKEN
  POCKET_ID_HOME — Pocket ID docker-compose directory
`)
}

func envOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func resolveToken(flagTok string) string {
	if flagTok != "" {
		return flagTok
	}
	t, _ := hubauth.LoadToken()
	return t
}

func readApplyBody(rest []string) string {
	for i := 0; i < len(rest); i++ {
		if rest[i] == "-f" && i+1 < len(rest) {
			b, err := os.ReadFile(rest[i+1])
			if err != nil {
				fatal(err)
			}
			return string(b)
		}
	}
	b, err := os.ReadFile("-")
	if err == nil {
		return string(b)
	}
	fatal("apply requires -f file")
	return ""
}

func printEnv(env *document.Envelope, format string) {
	printJSON(env, format)
}

func printJSON(v any, format string) {
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		fatal(err)
	}
	if format == "json" {
		fmt.Println(string(b))
		return
	}
	fmt.Println(string(b))
}

func fatal(v any) {
	fmt.Fprintln(os.Stderr, v)
	os.Exit(1)
}

func init() {
	_ = filepath.Join
	_ = strings.TrimSpace
}

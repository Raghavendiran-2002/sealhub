package main

import (
	"context"
	"flag"
	"fmt"
	"time"

	"github.com/raghavendiran/sealhub/internal/cli/pocket"
	"github.com/raghavendiran/sealhub/pkg/client"
)

func runPocket(server, token string, args []string) {
	if len(args) < 1 {
		fatal("usage: hub pocket backup|restore [-dir DIR] [-instance NAME] [-no-stop]")
	}
	fs := flag.NewFlagSet("pocket", flag.ExitOnError)
	home := fs.String("dir", "", "Pocket ID compose directory (default: POCKET_ID_HOME or Mac homelab path)")
	instance := fs.String("instance", "homelab", "instance name in pocket/ and secrets/ paths")
	noStop := fs.Bool("no-stop", false, "do not stop/start pocket-id compose service")
	_ = fs.Parse(args[1:])

	opt := pocket.Options{
		Home:        *home,
		Instance:    *instance,
		StopCompose: !*noStop,
	}
	c := pocket.ClientWithTimeout(client.New(server, token), 5*time.Minute)
	ctx := context.Background()

	switch args[0] {
	case "backup":
		if err := pocket.Backup(ctx, c, opt); err != nil {
			fatal(err)
		}
		fmt.Println("ok")
	case "restore":
		if err := pocket.Restore(ctx, c, opt); err != nil {
			fatal(err)
		}
		fmt.Println("ok")
	default:
		fatal("usage: hub pocket backup|restore")
	}
}

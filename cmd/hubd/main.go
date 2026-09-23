package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/raghavendiran/sealhub/pkg/api"
	"github.com/raghavendiran/sealhub/pkg/auth"
	"github.com/raghavendiran/sealhub/pkg/config"
	"github.com/raghavendiran/sealhub/pkg/crypto"
	"github.com/raghavendiran/sealhub/pkg/store"
)

func main() {
	cfgPath := os.Getenv("SEALHUB_CONFIG")
	if cfgPath == "" && len(os.Args) > 1 {
		cfgPath = os.Args[1]
	}
	if cfgPath == "" {
		cfgPath = "config.yaml"
	}
	cfg, err := config.Load(cfgPath)
	if err != nil {
		log.Fatalf("config: %v", err)
	}
	kr, err := crypto.LoadKeyRing(cfg.Encryption.KeyringFile)
	if err != nil {
		log.Fatalf("keyring: %v", err)
	}
	jwtSecret, err := auth.LoadJWTSecret(cfg.Auth.JWTSecretFile)
	if err != nil {
		log.Fatalf("jwt secret: %v", err)
	}
	eng := auth.NewEngine(cfg.Auth.BootstrapToken, jwtSecret)

	ctx := context.Background()
	gs, err := store.OpenOrClone(ctx, store.Options{
		LocalPath: cfg.Git.LocalPath,
		CloneURL:  cfg.CloneURL(),
		Branch:    cfg.GitHub.Branch,
		PATFile:   cfg.GitHub.Auth.PATFile,
		UseSSH:    cfg.GitAuthSSH(),
		Keyring:   kr,
	})
	if err != nil {
		log.Fatalf("store: %v", err)
	}

	srv := api.NewServer(gs, eng)
	srv.ReloadSystemAuth()

	go func() {
		t := time.NewTicker(cfg.PollDuration())
		defer t.Stop()
		for range t.C {
			if err := gs.Poll(context.Background()); err != nil {
				log.Printf("poll: %v", err)
			}
			srv.ReloadSystemAuth()
		}
	}()

	httpSrv := &http.Server{
		Addr:    cfg.Server.Listen,
		Handler: srv.Handler(),
	}
	go func() {
		log.Printf("sealhub hubd listening on %s", cfg.Server.Listen)
		if err := httpSrv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("listen: %v", err)
		}
	}()

	ch := make(chan os.Signal, 1)
	signal.Notify(ch, syscall.SIGINT, syscall.SIGTERM)
	<-ch
	shCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = httpSrv.Shutdown(shCtx)
}

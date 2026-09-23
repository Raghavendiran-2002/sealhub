package api

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/prometheus/client_golang/prometheus/promhttp"
	"gopkg.in/yaml.v3"
	"github.com/raghavendiran/sealhub/pkg/auth"
	"github.com/raghavendiran/sealhub/pkg/changes"
	"github.com/raghavendiran/sealhub/pkg/document"
	"github.com/raghavendiran/sealhub/pkg/store"
)

// Server is the HTTP API.
type Server struct {
	Store  *store.GitStore
	Auth   *auth.Engine
	Mux    *http.ServeMux
}

func NewServer(gs *store.GitStore, eng *auth.Engine) *Server {
	s := &Server{Store: gs, Auth: eng, Mux: http.NewServeMux()}
	s.routes()
	return s
}

func (s *Server) routes() {
	s.Mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	s.Mux.HandleFunc("/readyz", func(w http.ResponseWriter, _ *http.Request) {
		if !s.Store.Ready() {
			http.Error(w, "not ready", http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ready"))
	})
	s.Mux.Handle("/metrics", promhttp.Handler())
	s.Mux.HandleFunc("/api/v1/auth/providers", s.handleProviders)
	s.Mux.HandleFunc("/api/v1/auth/token", s.handleAuthToken)
	s.Mux.HandleFunc("/api/v1/documents/", s.handleDocumentPath)
	s.Mux.HandleFunc("/api/v1/documents", s.handleDocumentList)
	s.Mux.HandleFunc("/api/v1/changes", s.handleChanges)
}

func (s *Server) Handler() http.Handler {
	return s.Auth.Middleware(s.Mux)
}

func (s *Server) handleProviders(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	// issuers loaded in engine; return names only
	type prov struct {
		Name string `json:"name"`
	}
	var list []prov
	if raw, err := s.Store.ReadSystemFile("system/issuers.yaml"); err == nil {
		var iss auth.IssuersFile
		_ = s.Auth.LoadIssuersYAML(raw)
		var wrap struct {
			Document string `yaml:"document"`
		}
		if err := yaml.Unmarshal(raw, &wrap); err == nil && wrap.Document != "" {
			_ = yaml.Unmarshal([]byte(wrap.Document), &iss)
		} else {
			_ = yaml.Unmarshal(raw, &iss)
		}
		for _, i := range iss.Issuers {
			list = append(list, prov{Name: i.Name})
		}
	}
	auth.WriteJSON(w, http.StatusOK, map[string]any{"providers": list})
}

func (s *Server) handleAuthToken(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req struct {
		GrantType  string `json:"grant_type"`
		Issuer     string `json:"issuer"`
		IDToken    string `json:"id_token"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}
	sub, groups, err := s.Auth.ValidateIDToken(r.Context(), req.Issuer, req.IDToken)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	jwt, err := s.Auth.MintAPIJWT(sub, req.Issuer, groups, 8*time.Hour)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	auth.WriteJSON(w, http.StatusOK, map[string]string{"access_token": jwt, "token_type": "Bearer"})
}

func (s *Server) handleDocumentList(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	p, ok := auth.FromContext(r.Context())
	if !ok {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	prefix := r.URL.Query().Get("prefix")
	labelKey := ""
	labelVal := ""
	for k, v := range r.URL.Query() {
		if strings.HasPrefix(k, "label.") {
			labelKey = strings.TrimPrefix(k, "label.")
			labelVal = v[0]
		}
	}
	items := s.Store.List(prefix, labelKey, labelVal)
	var out []any
	for _, it := range items {
		if !s.Auth.Authorize(p, document.GitPath(it.Path), auth.ActionRead) {
			continue
		}
		out = append(out, map[string]any{
			"path":     it.Path,
			"metadata": it.Metadata,
		})
	}
	auth.WriteJSON(w, http.StatusOK, map[string]any{"documents": out})
}

func (s *Server) handleDocumentPath(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/api/v1/documents/")
	path = strings.TrimPrefix(path, "/")
	if path == "" {
		http.NotFound(w, r)
		return
	}
	p, ok := auth.FromContext(r.Context())
	if !ok {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	gitPath := document.GitPath(path)
	switch r.Method {
	case http.MethodGet:
		if !s.Auth.Authorize(p, gitPath, auth.ActionRead) {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		env, err := s.Store.GetDocument(path)
		if err != nil {
			if errors.Is(err, store.ErrNotFound) {
				http.NotFound(w, r)
				return
			}
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		auth.WriteJSON(w, http.StatusOK, env)
	case http.MethodPut:
		if strings.HasPrefix(path, "system/") && p.Kind != "bootstrap" {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		if !s.Auth.Authorize(p, gitPath, auth.ActionWrite) {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		body, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		var req struct {
			Document        string `json:"document"`
			ContentType     string `json:"contentType"`
			Encrypt         *bool  `json:"encrypt"`
			ExpectedVersion int    `json:"expectedVersion"`
		}
		if err := json.Unmarshal(body, &req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		if v := r.Header.Get("If-Match"); v != "" {
			if n, err := strconv.Atoi(v); err == nil {
				req.ExpectedVersion = n
			}
		}
		enc := document.DefaultEncryptForPath(path)
		if req.Encrypt != nil {
			enc = *req.Encrypt
		}
		owner := fmt.Sprintf("%s:%s", p.Kind, p.ID)
		env, err := s.Store.Apply(r.Context(), path, req.Document, req.ContentType, enc, req.ExpectedVersion, owner)
		if errors.Is(err, store.ErrConflict) {
			http.Error(w, "conflict", http.StatusConflict)
			return
		}
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		auth.WriteJSON(w, http.StatusOK, env)
	case http.MethodDelete:
		if !s.Auth.Authorize(p, gitPath, auth.ActionWrite) {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		ev, _ := strconv.Atoi(r.URL.Query().Get("version"))
		if err := s.Store.Delete(r.Context(), path, ev); err != nil {
			if errors.Is(err, store.ErrNotFound) {
				http.NotFound(w, r)
				return
			}
			if errors.Is(err, store.ErrConflict) {
				http.Error(w, "conflict", http.StatusConflict)
				return
			}
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	default:
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

func (s *Server) handleChanges(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	p, ok := auth.FromContext(r.Context())
	if !ok {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	prefix := r.URL.Query().Get("prefix")
	since, _ := strconv.ParseInt(r.URL.Query().Get("since"), 10, 64)
	broker := s.Store.Broker()

	if r.Header.Get("Accept") == "text/event-stream" {
		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache")
		flusher, ok := w.(http.Flusher)
		if !ok {
			http.Error(w, "streaming unsupported", http.StatusInternalServerError)
			return
		}
		for _, ev := range broker.Since(since, prefix) {
			if !s.Auth.Authorize(p, document.GitPath(ev.Path), auth.ActionRead) {
				continue
			}
			b, _ := json.Marshal(ev)
			_, _ = fmt.Fprintf(w, "data: %s\n\n", b)
			flusher.Flush()
		}
		ch := broker.Subscribe(32)
		defer broker.Unsubscribe(ch)
		for {
			select {
			case ev, ok := <-ch:
				if !ok {
					return
				}
				if prefix != "" && !strings.HasPrefix(ev.Path, prefix) && ev.Path != prefix {
					continue
				}
				if !s.Auth.Authorize(p, document.GitPath(ev.Path), auth.ActionRead) {
					continue
				}
				b, _ := json.Marshal(ev)
				_, _ = fmt.Fprintf(w, "data: %s\n\n", b)
				flusher.Flush()
			case <-r.Context().Done():
				return
			}
		}
	}
	var filtered []changes.Event
	for _, ev := range broker.Since(since, prefix) {
		if !s.Auth.Authorize(p, document.GitPath(ev.Path), auth.ActionRead) {
			continue
		}
		filtered = append(filtered, ev)
	}
	auth.WriteJSON(w, http.StatusOK, map[string]any{
		"revision": broker.Revision(),
		"events":   filtered,
	})
}

// ReloadSystemAuth loads tokens and issuers from git.
func (s *Server) ReloadSystemAuth() {
	if raw, err := s.Store.ReadSystemFile("system/tokens.yaml"); err == nil {
		_ = s.Auth.LoadTokensYAML(raw)
	}
	if raw, err := s.Store.ReadSystemFile("system/issuers.yaml"); err == nil {
		_ = s.Auth.LoadIssuersYAML(raw)
	}
}

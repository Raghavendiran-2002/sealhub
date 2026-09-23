package auth

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
	"gopkg.in/yaml.v3"
)

// Action is read or write.
type Action string

const (
	ActionRead  Action = "read"
	ActionWrite Action = "write"
)

// Principal identifies the caller.
type Principal struct {
	Kind   string   // bootstrap | token | oidc
	ID     string   // token id or sub
	Groups []string
}

// IssuerRule maps paths to group requirements.
type IssuerRule struct {
	Paths []string `yaml:"paths"`
	Read  ClaimReq `yaml:"read"`
	Write ClaimReq `yaml:"write"`
}

type ClaimReq struct {
	Authenticated bool     `yaml:"authenticated"`
	Groups        []string `yaml:"groups"`
}

// IssuerConfig is one OIDC issuer.
type IssuerConfig struct {
	Name      string       `yaml:"name"`
	Issuer    string       `yaml:"issuer"`
	Audiences []string     `yaml:"audiences"`
	JWKSURL   string       `yaml:"jwksURL"`
	Rules     []IssuerRule `yaml:"rules"`
}

// TokenRecord is a service token entry.
type TokenRecord struct {
	ID     string `yaml:"id"`
	Hash   string `yaml:"hash"`
	Scopes struct {
		Paths   []string `yaml:"paths"`
		Actions []string `yaml:"actions"`
	} `yaml:"scopes"`
}

// TokensFile is stored in system/tokens.yaml document body.
type TokensFile struct {
	Tokens []TokenRecord `yaml:"tokens"`
}

// IssuersFile is stored in system/issuers.yaml document body.
type IssuersFile struct {
	Issuers []IssuerConfig `yaml:"issuers"`
}

// Engine evaluates authorization.
type Engine struct {
	mu              sync.RWMutex
	bootstrapToken  string
	jwtSecret       []byte
	serviceTokens   []TokenRecord
	issuers         []IssuerConfig
	issuerRules     []IssuerRule // flattened for oidc jwt claims
}

func NewEngine(bootstrap string, jwtSecret []byte) *Engine {
	return &Engine{
		bootstrapToken: bootstrap,
		jwtSecret:      jwtSecret,
	}
}

func (e *Engine) LoadTokensYAML(raw []byte) error {
	var wrap struct {
		Document string `yaml:"document"`
	}
	if err := yaml.Unmarshal(raw, &wrap); err == nil && wrap.Document != "" {
		raw = []byte(wrap.Document)
	}
	var tf TokensFile
	if err := yaml.Unmarshal(raw, &tf); err != nil {
		return err
	}
	e.mu.Lock()
	e.serviceTokens = tf.Tokens
	e.mu.Unlock()
	return nil
}

func (e *Engine) LoadIssuersYAML(raw []byte) error {
	var wrap struct {
		Document string `yaml:"document"`
	}
	if err := yaml.Unmarshal(raw, &wrap); err == nil && wrap.Document != "" {
		raw = []byte(wrap.Document)
	}
	var iss IssuersFile
	if err := yaml.Unmarshal(raw, &iss); err != nil {
		// try direct issuers list
		if err2 := yaml.Unmarshal(raw, &iss); err2 != nil {
			return err
		}
	}
	e.mu.Lock()
	e.issuers = iss.Issuers
	var rules []IssuerRule
	for _, i := range iss.Issuers {
		rules = append(rules, i.Rules...)
	}
	e.issuerRules = rules
	e.mu.Unlock()
	return nil
}

// SealHubClaims for API JWT after OIDC exchange.
type SealHubClaims struct {
	jwt.RegisteredClaims
	Groups []string `json:"groups,omitempty"`
	Kind   string   `json:"kind"`
}

func (e *Engine) MintAPIJWT(sub, iss string, groups []string, ttl time.Duration) (string, error) {
	now := time.Now()
	claims := SealHubClaims{
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   sub,
			Issuer:    "sealhub",
			Audience:  jwt.ClaimStrings{"sealhub-api"},
			ExpiresAt: jwt.NewNumericDate(now.Add(ttl)),
			IssuedAt:  jwt.NewNumericDate(now),
		},
		Groups: groups,
		Kind:   "oidc",
	}
	t := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return t.SignedString(e.jwtSecret)
}

func (e *Engine) AuthenticateBearer(token string) (Principal, error) {
	if token == "" {
		return Principal{}, fmt.Errorf("missing token")
	}
	if e.bootstrapToken != "" && subtle.ConstantTimeCompare([]byte(token), []byte(e.bootstrapToken)) == 1 {
		return Principal{Kind: "bootstrap", ID: "bootstrap", Groups: []string{"admin"}}, nil
	}
	e.mu.RLock()
	defer e.mu.RUnlock()
	for _, tr := range e.serviceTokens {
		if err := bcrypt.CompareHashAndPassword([]byte(tr.Hash), []byte(token)); err == nil {
			return Principal{Kind: "token", ID: tr.ID}, nil
		}
	}
	princ, err := e.parseAPIJWT(token)
	if err != nil {
		return Principal{}, err
	}
	return princ, nil
}

func (e *Engine) parseAPIJWT(token string) (Principal, error) {
	t, err := jwt.ParseWithClaims(token, &SealHubClaims{}, func(t *jwt.Token) (interface{}, error) {
		if t.Method != jwt.SigningMethodHS256 {
			return nil, fmt.Errorf("unexpected signing method")
		}
		return e.jwtSecret, nil
	})
	if err != nil {
		return Principal{}, err
	}
	claims, ok := t.Claims.(*SealHubClaims)
	if !ok || !t.Valid {
		return Principal{}, fmt.Errorf("invalid jwt")
	}
	return Principal{Kind: "oidc", ID: claims.Subject, Groups: claims.Groups}, nil
}

func (e *Engine) Authorize(p Principal, gitPath string, action Action) bool {
	gitPath = strings.TrimPrefix(gitPath, "/")
	apiPath := strings.TrimPrefix(gitPath, "data/")

	if p.Kind == "bootstrap" {
		return true
	}

	e.mu.RLock()
	defer e.mu.RUnlock()

	if p.Kind == "token" {
		for _, tr := range e.serviceTokens {
			if tr.ID != p.ID {
				continue
			}
			if !tokenAllowsAction(tr, action) {
				return false
			}
			for _, pat := range tr.Scopes.Paths {
				if pathMatch(apiPath, strings.TrimPrefix(pat, "data/")) {
					return true
				}
			}
		}
		return false
	}

	for _, rule := range e.issuerRules {
		for _, pat := range rule.Paths {
			if !pathMatch("data/"+apiPath, pat) && !pathMatch(apiPath, strings.TrimPrefix(pat, "data/")) {
				continue
			}
			req := rule.Read
			if action == ActionWrite {
				req = rule.Write
			}
			if req.Authenticated {
				return true
			}
			for _, g := range req.Groups {
				for _, pg := range p.Groups {
					if g == pg {
						return true
					}
				}
			}
		}
	}
	return false
}

func tokenAllowsAction(tr TokenRecord, action Action) bool {
	if len(tr.Scopes.Actions) == 0 {
		return true
	}
	for _, a := range tr.Scopes.Actions {
		if Action(a) == action {
			return true
		}
	}
	return false
}

func pathMatch(path, pattern string) bool {
	pattern = strings.TrimPrefix(pattern, "data/")
	path = strings.TrimPrefix(path, "data/")
	if pattern == "**" || pattern == "*" {
		return true
	}
	if strings.HasSuffix(pattern, "/**") {
		pre := strings.TrimSuffix(pattern, "/**")
		return path == pre || strings.HasPrefix(path, pre+"/")
	}
	return path == pattern
}

// Middleware wraps handlers with auth.
func (e *Engine) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/healthz" || r.URL.Path == "/readyz" || r.URL.Path == "/metrics" {
			next.ServeHTTP(w, r)
			return
		}
		if r.URL.Path == "/api/v1/auth/providers" && r.Method == http.MethodGet {
			next.ServeHTTP(w, r)
			return
		}
		if r.URL.Path == "/api/v1/auth/token" && r.Method == http.MethodPost {
			next.ServeHTTP(w, r)
			return
		}
		authz := r.Header.Get("Authorization")
		if !strings.HasPrefix(authz, "Bearer ") {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		tok := strings.TrimPrefix(authz, "Bearer ")
		p, err := e.AuthenticateBearer(tok)
		if err != nil {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		ctx := context.WithValue(r.Context(), principalKey{}, p)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

type principalKey struct{}

func FromContext(ctx context.Context) (Principal, bool) {
	p, ok := ctx.Value(principalKey{}).(Principal)
	return p, ok
}

// HashToken bcrypt-hashes a plaintext token.
func HashToken(plain string) (string, error) {
	b, err := bcrypt.GenerateFromPassword([]byte(plain), bcrypt.DefaultCost)
	return string(b), err
}

// LoadJWTSecret reads or generates jwt secret bytes.
func LoadJWTSecret(path string) ([]byte, error) {
	if path != "" {
		b, err := os.ReadFile(path)
		if err != nil {
			return nil, err
		}
		return []byte(strings.TrimSpace(string(b))), nil
	}
	return []byte("dev-insecure-change-me"), nil
}

// WriteJSON helper.
func WriteJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

package auth

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// ValidateIDToken validates an OIDC id_token (signature verification when JWKSURL set is best-effort in v1).
func (e *Engine) ValidateIDToken(ctx context.Context, issuerName, idToken string) (sub string, groups []string, err error) {
	e.mu.RLock()
	var ic *IssuerConfig
	for i := range e.issuers {
		if e.issuers[i].Name == issuerName {
			ic = &e.issuers[i]
			break
		}
	}
	e.mu.RUnlock()
	if ic == nil {
		return "", nil, fmt.Errorf("unknown issuer %q", issuerName)
	}
	parser := jwt.NewParser()
	tok, _, err := parser.ParseUnverified(idToken, jwt.MapClaims{})
	if err != nil {
		return "", nil, err
	}
	claims, ok := tok.Claims.(jwt.MapClaims)
	if !ok {
		return "", nil, fmt.Errorf("invalid claims")
	}
	if iss, _ := claims["iss"].(string); iss != "" && iss != ic.Issuer {
		return "", nil, fmt.Errorf("issuer mismatch")
	}
	if exp, err := claims.GetExpirationTime(); err == nil && exp.Before(time.Now()) {
		return "", nil, fmt.Errorf("token expired")
	}
	sub, _ = claims["sub"].(string)
	groups = groupsFromClaims(claims)
	return sub, groups, nil
}

func groupsFromClaims(c jwt.MapClaims) []string {
	var out []string
	if g, ok := c["groups"].([]interface{}); ok {
		for _, v := range g {
			if s, ok := v.(string); ok {
				out = append(out, s)
			}
		}
	}
	if len(out) == 0 {
		if g, ok := c["groups"].(string); ok {
			for _, p := range strings.Split(g, ",") {
				if s := strings.TrimSpace(p); s != "" {
					out = append(out, s)
				}
			}
		}
	}
	return out
}

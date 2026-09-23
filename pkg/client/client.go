package client

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/raghavendiran/sealhub/pkg/changes"
	"github.com/raghavendiran/sealhub/pkg/document"
)

type Client struct {
	BaseURL    string
	Token      string
	HTTPClient *http.Client
}

func New(baseURL, token string) *Client {
	return &Client{
		BaseURL: strings.TrimRight(baseURL, "/"),
		Token:   token,
		HTTPClient: &http.Client{Timeout: 60 * time.Second},
	}
}

func (c *Client) auth(req *http.Request) {
	if c.Token != "" {
		req.Header.Set("Authorization", "Bearer "+c.Token)
	}
}

func (c *Client) Get(ctx context.Context, path string) (*document.Envelope, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.BaseURL+"/api/v1/documents/"+path, nil)
	if err != nil {
		return nil, err
	}
	c.auth(req)
	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotFound {
		return nil, fmt.Errorf("not found")
	}
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("get: %s", string(b))
	}
	var env document.Envelope
	if err := json.NewDecoder(resp.Body).Decode(&env); err != nil {
		return nil, err
	}
	return &env, nil
}

func (c *Client) List(ctx context.Context, prefix string) ([]map[string]any, error) {
	u, _ := url.Parse(c.BaseURL + "/api/v1/documents")
	q := u.Query()
	if prefix != "" {
		q.Set("prefix", prefix)
	}
	u.RawQuery = q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	if err != nil {
		return nil, err
	}
	c.auth(req)
	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	var out struct {
		Documents []map[string]any `json:"documents"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, err
	}
	return out.Documents, nil
}

type ApplyRequest struct {
	Document        string
	ContentType     string
	Encrypt         *bool
	ExpectedVersion int
}

func (c *Client) Apply(ctx context.Context, path string, ar ApplyRequest) (*document.Envelope, error) {
	body, _ := json.Marshal(map[string]any{
		"document":        ar.Document,
		"contentType":     ar.ContentType,
		"encrypt":         ar.Encrypt,
		"expectedVersion": ar.ExpectedVersion,
	})
	req, err := http.NewRequestWithContext(ctx, http.MethodPut, c.BaseURL+"/api/v1/documents/"+path, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	if ar.ExpectedVersion > 0 {
		req.Header.Set("If-Match", strconv.Itoa(ar.ExpectedVersion))
	}
	c.auth(req)
	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusConflict {
		return nil, fmt.Errorf("conflict")
	}
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("apply: %s", string(b))
	}
	var env document.Envelope
	if err := json.NewDecoder(resp.Body).Decode(&env); err != nil {
		return nil, err
	}
	return &env, nil
}

func (c *Client) Delete(ctx context.Context, path string, version int) error {
	u := c.BaseURL + "/api/v1/documents/" + path
	if version > 0 {
		u += "?version=" + strconv.Itoa(version)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodDelete, u, nil)
	if err != nil {
		return err
	}
	c.auth(req)
	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		b, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("delete: %s", string(b))
	}
	return nil
}

func (c *Client) Watch(ctx context.Context, since int64, prefix string, fn func(changes.Event) error) error {
	u, _ := url.Parse(c.BaseURL + "/api/v1/changes")
	q := u.Query()
	if since > 0 {
		q.Set("since", strconv.FormatInt(since, 10))
	}
	if prefix != "" {
		q.Set("prefix", prefix)
	}
	u.RawQuery = q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	if err != nil {
		return err
	}
	req.Header.Set("Accept", "text/event-stream")
	c.auth(req)
	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	buf := make([]byte, 0, 4096)
	tmp := make([]byte, 1024)
	for {
		n, err := resp.Body.Read(tmp)
		if n > 0 {
			buf = append(buf, tmp[:n]...)
			for {
				idx := bytes.Index(buf, []byte("\n\n"))
				if idx < 0 {
					break
				}
				frame := string(buf[:idx])
				buf = buf[idx+2:]
				if strings.HasPrefix(frame, "data: ") {
					var ev changes.Event
					if err := json.Unmarshal([]byte(strings.TrimPrefix(frame, "data: ")), &ev); err == nil {
						if err := fn(ev); err != nil {
							return err
						}
					}
				}
			}
		}
		if err != nil {
			if err == io.EOF {
				return nil
			}
			return err
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}
	}
}

func (c *Client) ExchangeIDToken(ctx context.Context, issuer, idToken string) (string, error) {
	body, _ := json.Marshal(map[string]string{
		"grant_type": "id_token",
		"issuer":     issuer,
		"id_token":   idToken,
	})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.BaseURL+"/api/v1/auth/token", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	var out struct {
		AccessToken string `json:"access_token"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return "", err
	}
	return out.AccessToken, nil
}

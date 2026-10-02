# RootOS metrics sharing (example)

Two Pis: **dashboard** on `100.114.97.68`, **metrics agent** on `100.66.190.37`.

## 1. Shared secret (same on both sides)

```bash
# Generate once (example — use your own in production)
export METRICS_TOKEN="$(openssl rand -hex 32)"
```

| Host | Variable | Where |
|------|----------|--------|
| Agent Pi | `METRICS_TOKEN` | `/etc/rootos/agent.env` |
| Dashboard Pi | `METRICS_REMOTE_TOKEN` | Podman env (compose) — same value as `METRICS_TOKEN` |

## 2. Agent (`pi@100.66.190.37`)

```bash
# /etc/rootos/agent.env
ROOTOS_IMAGE=ghcr.io/raghavendiran-2002/rootos:latest
ROOTOS_AGENT_LISTEN=0.0.0.0:9090
METRICS_TOKEN=your-64-char-hex-secret
```

```bash
sudo systemctl enable --now rootos-metrics-agent
curl -sf http://127.0.0.1:9090/health
curl -sf -H "Authorization: Bearer $METRICS_TOKEN" \
  http://127.0.0.1:9090/api/system-stats | jq .hostname,.cpu.percent
```

From the dashboard Pi (Tailscale):

```bash
curl -sf -H "Authorization: Bearer $METRICS_TOKEN" \
  http://100.66.190.37:9090/api/system-stats | jq .hostname
```

## 3. Dashboard config (`~/pocket-id/starry/config.yml`)

```yaml
title: "RootOS"
metrics_hosts:
  - id: live
    label: Live
    local: true
  - id: control
    label: Control plane
    url: "http://100.66.190.37:9090"
```

Podman compose env on live:

```yaml
environment:
  METRICS_REMOTE_TOKEN: ${METRICS_TOKEN}
```

## 4. Deploy from your Mac

```bash
cd sealhub
export METRICS_TOKEN='your-secret'
./hack/pi/deploy-rootos-all.sh
```

After login, the UI calls **`/api/system-stats/all`**; the server fetches the remote agent with the bearer token (not the browser).

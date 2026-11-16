# RootOS — setup through deployment (homelab)

End-to-end runbook for **RootOS** on two Raspberry Pis over Tailscale:

| Host | Tailscale IP | Role |
|------|----------------|------|
| **Live** | `100.114.97.68` | Dashboard (`rootos serve`, port **5000**), Pocket ID stack |
| **Control** | `100.97.65.127` | Metrics agent only (`rootos agent`, port **9090**) |

Image: **`ghcr.io/raghavendiran-2002/rootos:latest`** (multi-arch: `linux/arm64`, `linux/arm/v7`).

---

## Architecture

```text
Browser ──► Live Pi :5000 (RootOS dashboard)
                │
                ├── local /proc mounts → "Live" metrics
                │
                └── server-side HTTP + Bearer token
                        └──► Control Pi :9090 (metrics agent)
```

- The browser never calls the agent directly; after login, the dashboard uses **`GET /api/system-stats/all`** and fetches remote stats with **`METRICS_REMOTE_TOKEN`**.
- Agent exposes **`GET /health`** and **`GET /api/system-stats`** (optional **`Authorization: Bearer <METRICS_TOKEN>`**).

---

## 1. Prerequisites

### Both Pis

- SSH as **`pi`**, Tailscale connected.
- **64-bit OS** (`uname -m` → `aarch64`) uses the `arm64` image manifest automatically.

### Live Pi (`100.114.97.68`)

- **[Kiri](https://docs.runkiri.com/linux)** on Linux (`kiri.service`, `docker` / `docker compose`) — Pocket ID stack under `~/pocket-id`.
- **`~/pocket-id/starry/auth.yml`** with Pocket ID OIDC already configured (from prior Starry Cloud / RootOS setup).
- **Cloudflare Tunnel** token in `~/pocket-id/.env` as `TUNNEL_TOKEN` (remote ingress in Zero Trust; see [§7 Cloudflare Tunnel](#7-cloudflare-tunnel-zero-trust)).

### Control Pi (`100.97.65.127`)

- **Podman** (install if missing):

```bash
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y podman curl
```

- **Passwordless sudo** (for installing systemd unit under `/etc/systemd/system/`).

### Your Mac / CI

- **`gh`** CLI (optional, for watching CI).
- SSH key access to both Pis (`BatchMode=yes`).
- Git clone of **[sealhub](https://github.com/Raghavendiran-2002/sealhub)** on branch **`rootos`**.

### Pocket ID (OIDC)

- OIDC client for the dashboard (client ID + secret in `auth.yml`).
- Correct **redirect URI** registered (see [§6 OIDC](#6-oidc-pocket-id)).

---

## 2. Repository and CI (GHCR)

RootOS lives on the **`rootos`** branch (Rust app in repo root, not SealHub `hubd` on `main`).

### Build and push

Workflow: [`.github/workflows/rootos-image.yaml`](../../.github/workflows/rootos-image.yaml)

- Triggers: push to **`rootos`**, or **workflow_dispatch**.
- Platforms: **`linux/arm64`**, **`linux/arm/v7`** only (no amd64).
- Cross-compiled on GitHub **amd64** runners (Debian `crossbuild-essential-*`); layer cache via GHA.

After a green run:

```text
ghcr.io/raghavendiran-2002/rootos:latest
ghcr.io/raghavendiran-2002/rootos:<git-sha>
```

### Pull on a Pi

```bash
docker pull ghcr.io/raghavendiran-2002/rootos:latest
# or: sg kiri -c "docker pull ghcr.io/raghavendiran-2002/rootos:latest"
```

Public GHCR pull works without login; private packages need `docker login ghcr.io`.

---

## 3. Local development (optional)

```bash
cp config.example.yml config.yml
cp auth.example.yml auth.yml
docker compose build
docker compose run --rm rootos gen-auth   # if auth.yml needs keys
docker compose up -d
# http://localhost:5000
```

CLI:

```text
rootos serve      # dashboard (default)
rootos gen-auth     # generate auth.yml snippet
rootos agent        # metrics-only server :9090
```

---

## 4. Shared metrics secret

Generate **once**; use the **same value** on the agent and the dashboard.

```bash
export METRICS_TOKEN="$(openssl rand -hex 32)"
```

| Location | Variable | File / mechanism |
|----------|----------|------------------|
| Control Pi | `METRICS_TOKEN` | `/etc/rootos/agent.env` |
| Live Pi | `METRICS_TOKEN` → `METRICS_REMOTE_TOKEN` | `~/pocket-id/.env` + compose `environment` |

If **`METRICS_REMOTE_TOKEN`** is empty in the **`rootos`** container, the UI shows **Control plane → HTTP 401 Unauthorized** for all metrics.

---

## 5. Configuration files

### Dashboard — `~/pocket-id/starry/config.yml`

Example: [`hack/pi/rootos/config.yml`](rootos/config.yml)

```yaml
title: "RootOS"
subtitle: "Homelab dashboard"

# 0 = direct http://IP:5000 ; 1 = behind cloudflared / reverse proxy
trusted_proxy_hops: 0

metrics_hosts:
  - id: live
    label: Live
    local: true
  - id: control
    label: Control plane
    url: "http://100.97.65.127:9090"

services:
  # ... your service cards ...
```

### Dashboard — `~/pocket-id/starry/auth.yml`

- **`password_enabled: false`** if using OIDC only.
- **`oidc`**: `discovery_url`, `client_id`, `client_secret`, `scope`, `allowed_emails`.
- **`secure_cookie`**: see [§6 OIDC](#6-oidc-pocket-id).

### Live Pi — `~/pocket-id/.env`

Persist the metrics token so `docker compose` keeps it across recreates:

```bash
METRICS_TOKEN=<same-64-hex-as-agent>
ROOTOS_IMAGE=ghcr.io/raghavendiran-2002/rootos:latest
```

### Live Pi — `~/pocket-id/docker-compose.yaml`

Use the template: [`hack/pi/podman-compose/pocket-id/docker-compose.yaml`](podman-compose/pocket-id/docker-compose.yaml)

Important **`rootos`** service bits:

```yaml
  rootos:
    image: ${ROOTOS_IMAGE:-ghcr.io/raghavendiran-2002/rootos:latest}
    container_name: rootos
    network_mode: host   # required for Tailscale control-plane metrics egress
    environment:
      METRICS_REMOTE_TOKEN: ${METRICS_TOKEN:-}
    volumes:
      - ./starry/config.yml:/app/config.yml:ro
      - ./starry/auth.yml:/app/auth.yml:ro
      # host /proc, /sys, /etc/hostname mounts for Live metrics ...
```

**`network_mode: host`** binds port **5000** on the Pi directly (no `ports:` mapping). Remote metrics then work over Tailscale; cloudflared must reach the dashboard via the bridge gateway — see [§7](#7-cloudflare-tunnel-zero-trust).

Stop the old **`starry-cloud`** container when switching to **`rootos`** (same port 5000).

### Control Pi — `/etc/rootos/agent.env`

Example: [`hack/pi/rootos-metrics-agent/env.example`](rootos-metrics-agent/env.example)

```bash
ROOTOS_IMAGE=ghcr.io/raghavendiran-2002/rootos:latest
ROOTOS_AGENT_LISTEN=0.0.0.0:9090
METRICS_TOKEN=<your-64-hex-secret>
```

Mode **`600`**, owned by **`pi`**.

### Control Pi — systemd

Unit file: [`hack/pi/rootos-metrics-agent/rootos-metrics-agent.service`](rootos-metrics-agent/rootos-metrics-agent.service)

- Runs **`podman run -d`** as **root** (so `sudo podman ps` shows the container).
- Binds host **`9090`**, mounts host `/proc` and `/sys` for real hardware stats.

```bash
sudo cp rootos-metrics-agent.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now rootos-metrics-agent
```

---

## 6. OIDC (Pocket ID)

### Redirect URI (required)

Register the **callback** path, **not** `/login`:

| How you open the dashboard | Redirect URI in Pocket ID |
|----------------------------|---------------------------|
| Tailscale IP, HTTP | `http://100.114.97.68:5000/login/oidc/callback` |
| Public HTTPS (cloudflared) | `https://home.raghavendiran.cloud/login/oidc/callback` |

Must match **scheme, host, port, and path** exactly.

### `auth.yml` cookies and proxy

| Access pattern | `secure_cookie` | `trusted_proxy_hops` |
|----------------|-----------------|----------------------|
| `http://100.114.97.68:5000` | **`false`** | **`0`** |
| HTTPS via cloudflared | **`true`** | **`1`** |

**Symptom:** OIDC succeeds at Pocket ID but you land on **`/login` again** in a loop.

**Cause:** `secure_cookie: true` over **HTTP** — the browser drops the session cookie.

**Fix:**

```bash
sed -i 's/secure_cookie: true/secure_cookie: false/' ~/pocket-id/starry/auth.yml
cd ~/pocket-id && podman compose up -d --force-recreate rootos
```

Use a private window or clear site cookies after changes.

---

## 7. Cloudflare Tunnel (Zero Trust)

The live stack runs **`pocket-id-cloudflared`** with **`tunnel --no-autoupdate run`** and **`TUNNEL_TOKEN`** from `~/pocket-id/.env`. Public hostnames and upstream URLs are configured in **[Cloudflare One](https://one.dash.cloudflare.com/) → Networks → Tunnels →** your tunnel → **Published application routes** (not in this git repo).

**Order matters** — first match wins.

| Public hostname | Service (HTTP) | Notes |
|-----------------|------------------|--------|
| `id.raghavendiran.cloud` | **`http://pocket-id:1411`** | Pocket ID stays on the compose bridge; name **`pocket-id`** resolves for cloudflared. |
| `home.raghavendiran.cloud` | **`http://172.18.0.1:5000`** | RootOS uses **`network_mode: host`** — it is **not** on Docker DNS as **`rootos`**. Use the compose **gateway IP** to reach host port **5000** from the bridge network. |

**Do not** use **`http://rootos:5000`** for home after host networking — cloudflared logs `lookup rootos on 127.0.0.11:53: no such host` and the site returns **502**.

If the gateway is not `172.18.0.1` (network recreation, Kiri upgrade), on **live**:

```bash
docker inspect pocket-id-cloudflared --format '{{range .NetworkSettings.Networks}}{{.Gateway}}{{end}}'
```

Update the **home** route to `http://<that-ip>:5000`.

**Alternative:** set home to **`http://127.0.0.1:5000`** only if **cloudflared** also uses **`network_mode: host`** (same as RootOS).

**Unchanged when migrating Podman → Kiri:** `TUNNEL_TOKEN`, DNS CNAMEs, Pocket ID redirect `https://id.raghavendiran.cloud/...`, RootOS redirect `https://home.raghavendiran.cloud/login/oidc/callback`, **`trusted_proxy_hops: 1`** in `auth.yml` for HTTPS via tunnel.

Quick check from your laptop:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://home.raghavendiran.cloud/
curl -sS -o /dev/null -w '%{http_code}\n' https://id.raghavendiran.cloud/
```

---

## 8. Deploy from your Mac (recommended)

From sealhub repo root on branch **`rootos`**:

```bash
chmod +x hack/pi/deploy-rootos-*.sh

export METRICS_TOKEN='your-shared-secret'
export ROOTOS_IMAGE='ghcr.io/raghavendiran-2002/rootos:latest'
export LIVE_HOST='100.114.97.68'
export REMOTE_HOST='100.97.65.127'

./hack/pi/deploy-rootos-all.sh
```

Scripts:

| Script | Purpose |
|--------|---------|
| [`deploy-rootos-all.sh`](deploy-rootos-all.sh) | Agent on control Pi, then dashboard on live Pi |
| [`deploy-rootos-agent-ssh.sh`](deploy-rootos-agent-ssh.sh) | Control Pi only: `.env`, systemd, pull, start |
| [`deploy-rootos-live-ssh.sh`](deploy-rootos-live-ssh.sh) | Live Pi: config, compose, `.env`, recreate **`rootos`** |

`deploy-rootos-live-ssh.sh` writes **`METRICS_TOKEN`** into **`~/pocket-id/.env`** when set.

---

## 9. Manual verification

### Control Pi — agent

```bash
curl -sf http://127.0.0.1:9090/health
# expect: ok

source /etc/rootos/agent.env
curl -sf -H "Authorization: Bearer $METRICS_TOKEN" \
  http://127.0.0.1:9090/api/system-stats | head -c 200
```

```bash
sudo systemctl status rootos-metrics-agent
sudo podman ps   # container rootos-metrics-agent
```

### Live Pi — dashboard

```bash
curl -sf http://127.0.0.1:5000/health
podman exec rootos printenv METRICS_REMOTE_TOKEN | wc -c   # expect 65 (64 + newline)
podman ps --filter name=rootos
```

### Live → Control (same as dashboard server fetch)

```bash
TOKEN=$(grep ^METRICS_TOKEN= ~/pocket-id/.env | cut -d= -f2-)
curl -sf -H "Authorization: Bearer $TOKEN" \
  http://100.97.65.127:9090/api/system-stats | jq .hostname,.memory.percent
```

### UI

1. Open dashboard, sign in with Pocket ID.
2. Two sections: **Live** (local) and **Control plane** (remote hostname, not `--` or 401).

---

## 10. Troubleshooting

| Symptom | Likely cause | Fix |
|---------|----------------|-----|
| **`home.raghavendiran.cloud` → 502** | Tunnel still points at **`http://rootos:5000`** | Set home service to **`http://172.18.0.1:5000`** ([§7](#7-cloudflare-tunnel-zero-trust)) |
| Control plane: **HTTP 401** | Empty **`METRICS_REMOTE_TOKEN`** in `rootos` container | Set **`METRICS_TOKEN`** in `~/pocket-id/.env`, recreate container |
| Control plane: **request failed** (not 401) | Bridge container cannot reach Tailscale | Keep **`network_mode: host`** on **`rootos`** |
| OIDC loop back to login | **`secure_cookie: true`** on HTTP | Set **`secure_cookie: false`**, recreate `rootos` |
| OIDC “invalid redirect” at IdP | Wrong callback URL | Use **`/login/oidc/callback`**, not `/login` |
| Agent: connection refused on :9090 | Systemd unit or port conflict | `sudo systemctl restart rootos-metrics-agent`; see [`rootos-metrics-agent.service`](rootos-metrics-agent/rootos-metrics-agent.service) |
| `podman: command not found` on control Pi | Podman not installed | `apt install podman` (agent still uses Podman there) |
| Live metrics OK, remote `--` | Tailscale/firewall or wrong URL in `metrics_hosts` | Check `url: http://100.97.65.127:9090` from live Pi with curl + token |
| Port 5000 bind error | **`starry-cloud`** still running | Remove old container, then `docker compose up -d --force-recreate rootos` |

---

## 11. File reference (repo)

| Path | Description |
|------|-------------|
| [`app/`](../../app/) | Rust source (`rootos` binary) |
| [`Dockerfile`](../../Dockerfile) | Pi cross-build + bookworm-slim runtime |
| [`.github/workflows/rootos-image.yaml`](../../.github/workflows/rootos-image.yaml) | GHCR publish |
| [`hack/pi/rootos/`](rootos/) | Live `config.yml`, standalone `docker-compose.yml` |
| [`hack/pi/podman-compose/pocket-id/`](podman-compose/pocket-id/) | Full Pocket ID + RootOS + cloudflared compose |
| [`hack/pi/rootos-metrics-agent/`](rootos-metrics-agent/) | systemd unit + env example |
| [`hack/pi/METRICS-SHARING.example.md`](METRICS-SHARING.example.md) | Short metrics + OIDC cheat sheet |

---

## 12. SealHub backups (live + K8s)

| Script | Where | Purpose |
|--------|--------|---------|
| [`backup-live-snapshot.sh`](backup-live-snapshot.sh) | **live** Pi | Pocket ID DB, `live/ssh`, RootOS `starry-cloud` + compose → **sealhub-data** |
| [`hack/k8s/collect-rpi-control-plane-on-pi.sh`](../k8s/collect-rpi-control-plane-on-pi.sh) | **control plane** | Refresh `/data/rpi-control-plane` + OIDC bundle |
| [`hack/k8s/store-rpi-control-plane-to-sealhub.sh`](../k8s/store-rpi-control-plane-to-sealhub.sh) | **Mac** (hub CLI) | `RPI_DATA=/tmp/...` or SSH collect → `data/rpi-control-plane/` |

Defaults: [`homelab-env.sh`](homelab-env.sh) (`LIVE_HOST`, `CONTROL_HOST`, hub URL).

---

## 13. Related SealHub (`main` branch)

The **`main`** branch is **SealHub** (`hubd`, config in GitHub). It previously documented Starry Cloud under `~/pocket-id` and backup paths like `live/starry-cloud/` in **sealhub-data**. RootOS on **`rootos`** replaces the dashboard image and naming; you can back up live files with `hub apply live/rootos/...` if you use SealHub on the live Pi.

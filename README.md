# RootOS

A self-hosted dashboard for personal services with live status checks, **multi-host** system resource monitoring, and protected access (password and/or OIDC).

<img width="1264" height="681" alt="Screenshot 2026-09-30 164536" src="https://github.com/user-attachments/assets/eca6afae-89dc-4619-aa6a-0b54e93b0e63" />

## Homelab deploy (Pi + GHCR)

Full runbook (architecture, CI, metrics agent, Pocket ID OIDC, deploy scripts, troubleshooting):

**[hack/pi/ROOTOS-DEPLOY.md](hack/pi/ROOTOS-DEPLOY.md)**

Quick deploy from your Mac (after image is on GHCR):

```bash
export METRICS_TOKEN="$(openssl rand -hex 32)"
./hack/pi/deploy-rootos-all.sh
```

Image: `ghcr.io/raghavendiran-2002/rootos:latest` (built on push to branch **`rootos`**).

## Configuration

The app uses `config.yml` for dashboard content and `auth.yml` for authentication. Copy from examples:

```sh
cp config.example.yml config.yml
cp auth.example.yml auth.yml
```

- **OIDC:** register **`https://your-host/login/oidc/callback`** at the identity provider (not `/login`).
- **Multi-host metrics:** run `rootos agent` on other machines; list them under **`metrics_hosts`** in `config.yml`. Set **`METRICS_TOKEN`** on the agent and **`METRICS_REMOTE_TOKEN`** on the dashboard (same value). See [METRICS-SHARING.example.md](hack/pi/METRICS-SHARING.example.md).

## Local run (dev)

```sh
docker compose build
docker compose run --rm rootos gen-auth
docker compose up -d
```

Dashboard: `http://localhost:5000`

Metrics agent (other host):

```sh
docker compose run --rm -p 9090:9090 -e METRICS_TOKEN=dev-secret rootos agent
```

## CLI

```text
rootos serve      # dashboard (default)
rootos gen-auth   # interactive auth.yml generator
rootos agent      # metrics API only (:9090)
```

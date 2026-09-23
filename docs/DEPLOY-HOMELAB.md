# SealHub homelab deployment (Pi 4 / Pi 3)

**Primary Pi runbook:** **[PI-SETUP.md](PI-SETUP.md)** — bootstrap, Podman, CLI, permissions, git apply, troubleshooting.

**CI deploy to Pi:** **[DEPLOY-CI.md](DEPLOY-CI.md)**.

## Quick start (Pi 4 / arm64)

```bash
git clone --depth 1 git@github.com:Raghavendiran-2002/sealhub.git ~/sealhub
cd ~/sealhub
chmod +x hack/pi/podman-setup.sh
export SUDO_PASS='your-pi-sudo-password'
./hack/pi/podman-setup.sh
```

Data repo: **https://github.com/Raghavendiran-2002/sealhub-data** (samples under `data/config/homelab/`, `data/secrets/homelab/`).

Image: **`ghcr.io/raghavendiran-2002/sealhub/hubd:0.1-latest`**.

## Pi 3 (arm/v7) — operator only

Deploy `sealhub-operator` with `linux/arm/v7`. Do not schedule hubd on 1 GB nodes.

```bash
kubectl apply -f deploy/operator/
kubectl apply -f deploy/samples/hubpull-secret.yaml
```

Create read token:

```bash
export SEALHUB_TOKEN=<bootstrap>
hub token create --id k8s-default --read 'data/secrets/default/**'
kubectl create secret generic sealhub-read-token --from-literal=token=<plaintext>
```

## Token rotation

1. Mint new service token via `hub` (admin OIDC or bootstrap).
2. Update Kubernetes Secret; operator picks up on next reconcile.
3. Revoke old hash in `system/tokens.yaml` via apply.

## TLS

Terminate TLS at Caddy/Traefik; hubd listens HTTP on `:8080` behind the proxy. Set `server.externalURL` in `/etc/sealhub/config.yaml` to the public URL.

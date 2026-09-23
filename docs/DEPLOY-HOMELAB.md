# SealHub homelab deployment (Pi 4 / Pi 3)

## Pi 4 (arm64) — hubd with Podman (recommended)

Private data repo: **https://github.com/Raghavendiran-2002/sealhub-data** (sample config + secret under `data/`).

On the Pi (SSH as `pi`), with GitHub SSH access configured:

```bash
git clone --depth 1 git@github.com:Raghavendiran-2002/sealhub.git
cd sealhub
chmod +x hack/pi/podman-setup.sh
export SUDO_PASS='your-pi-sudo-password'   # script uses sudo for /etc/sealhub
./hack/pi/podman-setup.sh
```

This pulls `ghcr.io/raghavendiran-2002/sealhub/hubd:0.1.4`, adds `git`/`openssh` (hubd needs git), clones `sealhub-data`, and verifies API fetch of:

- `config/homelab/settings.yaml`
- `secrets/homelab/sample.yaml`

Default bootstrap token: `pi-homelab-bootstrap-change-me` (override with `BOOTSTRAP_TOKEN=...`).

If GHCR pull fails (private package), run `podman login ghcr.io` with a GitHub PAT that has `read:packages`.

Add the Pi deploy key or user SSH key to the **sealhub-data** repo (Settings → Deploy keys or collaborator).

## Pi 4 — manual container (alternative)

1. Create GitHub repo `sealhub-data` with `system/issuers.yaml`, `system/tokens.yaml`, and `data/` tree.
2. Generate keyring: `head -c 32 /dev/urandom | base64 > keyring`.
3. Run container:

```bash
docker run -d --name hubd \
  -p 8080:8080 \
  -v ./config.yaml:/config/config.yaml:ro \
  -v ./github-pat:/run/secrets/github-pat:ro \
  -v ./keyring:/run/secrets/keyring:ro \
  -v hubd-git:/var/lib/sealhub/repo \
  ghcr.io/<org>/sealhub/hubd:<tag> /config/config.yaml
```

4. Set `server.externalURL` to your TLS URL (Caddy on Pi 4).
5. Register OIDC client with device code + redirect `http://127.0.0.1:*` for CLI PKCE.

## Pi 3 (arm/v7) — operator only

Deploy `sealhub-operator` image with `linux/arm/v7`. Do not schedule hubd on 1 GB nodes.

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

Terminate TLS at Caddy/Traefik; hubd listens HTTP on `:8080` behind the proxy.

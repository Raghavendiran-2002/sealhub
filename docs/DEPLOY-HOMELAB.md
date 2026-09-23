# SealHub homelab deployment (Pi 4 / Pi 3)

## Pi 4 (arm64) — hubd

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

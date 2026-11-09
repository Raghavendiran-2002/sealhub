# Homelab deploy quick reference

Full hubd bootstrap: [pi-setup.md](pi-setup.md). CI: [../ci/README.md](../ci/README.md).

## Pi 4 — hubd + Podman

```bash
git clone git@github.com:Raghavendiran-2002/sealhub.git ~/sealhub
cd ~/sealhub
chmod +x hack/pi/podman-setup.sh
export SUDO_PASS='...'
./hack/pi/podman-setup.sh
```

Image: `ghcr.io/raghavendiran-2002/sealhub/hubd:0.1-latest`. Data repo: **sealhub-data**.

## Pi 3 — operator only

Do not run hubd on 1 GB nodes. `kubectl apply -f deploy/operator/` + HubPull sample.

## RootOS (branch `rootos`)

```bash
METRICS_TOKEN=... hack/pi/deploy-rootos-all.sh
```

See `hack/pi/ROOTOS-DEPLOY.md` in repo.

## Token rotation

Mint via `hub token create`, update consumers, revoke old token in `system/tokens.yaml` via admin flow.

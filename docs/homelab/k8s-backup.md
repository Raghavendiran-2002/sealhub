# Control plane backup (`rpi-control-plane/`)

Parent: [README.md](README.md). Typical node name: `rpi4-control-plane`.

## On-node collect

From a checkout of **this repo** on the control plane:

```bash
# Optional: cluster namespace dump script (not in sealhub — set if you use one)
export K8S_REPO="${K8S_REPO:-$HOME/sibling-kubernetes-repo}"

bash hack/k8s/collect-rpi-control-plane-on-pi.sh
```

`collect-rpi-control-plane-on-pi.sh` writes under `RPI_BACKUP_ROOT` (default `/data/rpi-control-plane/`), copies cluster credentials and OIDC material, and may call `${K8S_REPO}/kubernetes/scripts/backup-rpi-control-plane.sh` when that file exists.

## Push to hub (workstation)

```bash
export SEALHUB_SERVER=http://100.114.97.68:8080 SEALHUB_TOKEN=...
./hack/k8s/store-rpi-control-plane-to-sealhub.sh
# or: RPI_DATA=/tmp/rpi-cp-backup ./hack/k8s/store-rpi-control-plane-to-sealhub.sh
```

Encryption rules in script:

- `secrets/secrets.yaml` → **`-encrypt`**
- `secrets/sealedsecrets.yaml` → **`-no-encrypt`**
- `_cluster/credentials/*`, OIDC secrets → **`-encrypt`**

SSH keys: `hack/k8s/store-rpi-control-plane-ssh-to-sealhub.sh` when keys exist on the node.

## Layout per app

| File | Envelope |
|------|----------|
| `config/configmaps.yaml`, `config/helmreleases.yaml` | plaintext |
| `secrets/secrets.yaml` | encrypted |
| `secrets/sealedsecrets.yaml` | plaintext (Bitnami ciphertext inside) |

Also: `_cluster/oidc/`, `_cluster/credentials/`.

## Read back

```bash
hub get rpi-control-plane/_cluster/oidc/kubernetes-oidc.yaml
```

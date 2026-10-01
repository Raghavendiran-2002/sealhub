# rpi4-control-plane → SealHub

Kubernetes control plane **`rpi4-control-plane`** (Tailscale e.g. `100.66.190.37`) exports live cluster state to **`/data/rpi-control-plane/<app>/{config,secrets}/`**, then SealHub stores the same layout under **`data/rpi-control-plane/`** in [sealhub-data](https://github.com/Raghavendiran-2002/sealhub-data).

| On Pi | SealHub API path | Encryption |
|-------|------------------|------------|
| `~/.ssh/id_ed25519` | `rpi-control-plane/ssh/id_ed25519` | yes |
| `~/.ssh/id_ed25519.pub` | `rpi-control-plane/ssh/id_ed25519.pub` | no |
| `cloudflare/config/configmaps.yaml` | `rpi-control-plane/cloudflare/config/configmaps.yaml` | no |
| `cloudflare/secrets/sealedsecrets.yaml` | `rpi-control-plane/cloudflare/secrets/sealedsecrets.yaml` | yes |
| `_cluster/credentials/admin.conf` | `rpi-control-plane/_cluster/credentials/admin.conf` | yes |
| `_cluster/oidc/kubernetes-oidc.yaml` | client id/secret, issuer, discovery URL, callbacks | yes |
| `_cluster/oidc/kubeconfig-oidc.yaml` | kubectl oidc-login exec config | yes |
| `_cluster/oidc/callback-urls.yaml` | Pocket ID redirect URIs | no |
| `_cluster/oidc/apiserver-oidc-flags.txt` | live apiserver `--oidc-*` flags | no |
| `_cluster/oidc/headlamp-helmrelease.yaml` | Headlamp OIDC (callback `…/oidc-callback`) | no |

Apps backed up: `flux`, `sealed-secrets`, `tailscale`, `cloudflare`, `headlamp`, `cert-manager`, `kube-system`, `monitoring`.

## On the Pi

```bash
# Uses Kubernetes-Home-Lab/kubernetes/scripts/backup-rpi-control-plane.sh
SUDO_PASS=... bash ~/sealhub/hack/k8s/collect-rpi-control-plane-on-pi.sh
```

Requires `KUBECONFIG=/etc/kubernetes/admin.conf` (cluster-admin). Do not use a broken `~/.kube/config` that points at an unreachable API URL.

## From your Mac (hubd on `live`)

```bash
source ~/.config/sealhub/env
export RPI_HOST=100.66.190.37 RPI_PASS='...'
./hack/k8s/store-rpi-control-plane-to-sealhub.sh
```

Pi SSH key pair (same layout as `live/ssh/*` on hub `live`):

```bash
source ~/.config/sealhub/env
./hack/k8s/store-rpi-control-plane-ssh-to-sealhub.sh
```

Restore: `hub get rpi-control-plane/cloudflare/secrets/sealedsecrets.yaml` (decrypts with hubd keyring).

Homelab GitOps source: `~/Desktop/Home-Lab/Kubernetes-Home-Lab` — Flux root `kubernetes/flux/clusters/homelab/`.

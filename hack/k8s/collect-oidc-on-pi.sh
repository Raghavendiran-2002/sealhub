#!/usr/bin/env bash
# Run ON rpi4-control-plane: write /data/rpi-control-plane/_cluster/oidc/* for SealHub.
set -euo pipefail

ROOT="${RPI_BACKUP_ROOT:-/data/rpi-control-plane}/_cluster/oidc"
SUDO_PASS="${SUDO_PASS:-}"
K8S_REPO="${K8S_REPO:-$HOME/Kubernetes-Home-Lab}"

sudo_cmd() {
  if [[ -n "$SUDO_PASS" ]]; then echo "$SUDO_PASS" | sudo -S "$@"; else sudo "$@"; fi
}

mkdir -p "$ROOT"

issuer_url="https://id.raghavendiran.cloud"
discovery_url="${issuer_url%/}/.well-known/openid-configuration"

apiserver_file="/etc/kubernetes/manifests/kube-apiserver.yaml"
if sudo_cmd test -r "$apiserver_file"; then
  sudo_cmd grep -E '^\s*- --oidc-' "$apiserver_file" >"${ROOT}/apiserver-oidc-flags.txt" || true
fi

if [[ -f /etc/kubernetes/config-oidc ]]; then
  sudo_cmd cp /etc/kubernetes/config-oidc "${ROOT}/kubeconfig-oidc.yaml"
  sudo_cmd chown "$(id -un):$(id -gn)" "${ROOT}/kubeconfig-oidc.yaml"
  chmod 600 "${ROOT}/kubeconfig-oidc.yaml"
fi

client_id=""
client_secret=""
if [[ -f "${ROOT}/kubeconfig-oidc.yaml" ]]; then
  client_id="$(grep -oE '(--oidc-client-id=)[^ ]+' "${ROOT}/kubeconfig-oidc.yaml" | head -1 | cut -d= -f2- || true)"
  client_secret="$(grep -oE '(--oidc-client-secret=)[^ ]+' "${ROOT}/kubeconfig-oidc.yaml" | head -1 | cut -d= -f2- || true)"
  issuer_url="$(grep -oE '(--oidc-issuer-url=)[^ ]+' "${ROOT}/kubeconfig-oidc.yaml" | head -1 | cut -d= -f2- || echo "$issuer_url")"
  discovery_url="${issuer_url%/}/.well-known/openid-configuration"
fi

headlamp_hr="${K8S_REPO}/kubernetes/flux/clusters/homelab/apps/monitoring/headlamp-helmrelease.yaml"
headlamp_callback="https://dashboard.raghavendiran.cloud/oidc-callback"
if [[ -f "$headlamp_hr" ]]; then
  cp "$headlamp_hr" "${ROOT}/headlamp-helmrelease.yaml"
  headlamp_callback="$(grep -E 'callbackURL:' "$headlamp_hr" | head -1 | sed -E 's/.*callbackURL:[[:space:]]*//' || echo "$headlamp_callback")"
fi

cat >"${ROOT}/callback-urls.yaml" <<EOF
# Pocket ID OIDC client "Kubernetes" — Headlamp + apiserver + kubectl (see docs/agents/secrets.md)
callback_urls:
  - ${headlamp_callback}
  - http://localhost:8000
  - http://127.0.0.1:8000
EOF

cat >"${ROOT}/kubernetes-oidc.yaml" <<EOF
# Kubernetes API OIDC (Pocket ID) — encrypted in SealHub (contains client_secret).
issuer_url: ${issuer_url}
oidc_discovery_url: ${discovery_url}
client_id: ${client_id}
client_secret: ${client_secret}
apiserver_username_claim: email
apiserver_groups_claim: groups
scopes:
  - openid
  - email
  - profile
  - groups
headlamp:
  issuer_url: ${issuer_url}
  callback_url: ${headlamp_callback}
  public_url: https://dashboard.raghavendiran.cloud
  cluster_service: http://headlamp.headlamp.svc.cluster.local:80
EOF
chmod 600 "${ROOT}/kubernetes-oidc.yaml"

rm -f "${ROOT}/oauth2-proxy-helmrelease.yaml" 2>/dev/null || true
echo "OIDC bundle -> ${ROOT}"

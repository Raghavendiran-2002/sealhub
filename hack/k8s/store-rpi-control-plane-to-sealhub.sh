#!/usr/bin/env bash
# Push /data/rpi-control-plane from rpi4-control-plane into sealhub-data (data/rpi-control-plane/...).
#
# From Mac:
#   RPI_HOST=100.66.190.37 RPI_PASS=... SEALHUB_TOKEN=... ./hack/k8s/store-rpi-control-plane-to-sealhub.sh
#
# Local tree only (skip SSH):
#   RPI_DATA=/path/to/rpi-control-plane ./hack/k8s/store-rpi-control-plane-to-sealhub.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RPI_HOST="${RPI_HOST:-100.66.190.37}"
RPI_USER="${RPI_USER:-pi}"
RPI_PASS="${RPI_PASS:-}"
WORK="${TMPDIR:-/tmp}/rpi-control-plane-$$"
trap 'rm -rf "$WORK"' EXIT

export SEALHUB_SERVER="${SEALHUB_SERVER:-http://192.168.1.14:8080}"
HUB="${HUB:-$ROOT/bin/hub}"
[[ -x "$HUB" ]] || HUB="$(command -v hub)"
[[ -n "${SEALHUB_TOKEN:-}" ]] || { echo "Set SEALHUB_TOKEN" >&2; exit 1; }

if [[ -n "${RPI_DATA:-}" ]]; then
  DATA="$RPI_DATA"
else
  command -v sshpass >/dev/null || { echo "sshpass required for SSH collect" >&2; exit 1; }
  [[ -n "$RPI_PASS" ]] || { echo "Set RPI_PASS for SSH" >&2; exit 1; }
  SSH=(sshpass -p "$RPI_PASS" ssh -o StrictHostKeyChecking=no "${RPI_USER}@${RPI_HOST}")
  SCP=(sshpass -p "$RPI_PASS" scp -o StrictHostKeyChecking=no)

  "${SCP[@]}" "${ROOT}/hack/k8s/collect-oidc-on-pi.sh" "${RPI_USER}@${RPI_HOST}:/tmp/collect-oidc-on-pi.sh"

  "${SSH[@]}" "SUDO_PASS='$RPI_PASS' bash -s" <<'REMOTE' || true
set -euo pipefail
if [[ -f "$HOME/Kubernetes-Home-Lab/kubernetes/scripts/backup-rpi-control-plane.sh" ]]; then
  SUDO_PASS="${SUDO_PASS:-}" sudo env KUBECONFIG=/etc/kubernetes/admin.conf bash "$HOME/Kubernetes-Home-Lab/kubernetes/scripts/backup-rpi-control-plane.sh"
fi
if [[ -f /tmp/collect-oidc-on-pi.sh ]]; then
  SUDO_PASS="${SUDO_PASS:-}" bash /tmp/collect-oidc-on-pi.sh
elif [[ -f "$HOME/sealhub/hack/k8s/collect-oidc-on-pi.sh" ]]; then
  SUDO_PASS="${SUDO_PASS:-}" bash "$HOME/sealhub/hack/k8s/collect-oidc-on-pi.sh"
fi
sudo chown -R pi:pi /data/rpi-control-plane 2>/dev/null || true
REMOTE

  mkdir -p "$WORK"
  "${SCP[@]}" -r "${RPI_USER}@${RPI_HOST}:/data/rpi-control-plane/." "$WORK/"
  DATA="$WORK"
fi

apply_one() {
  local f="$1"
  local rel="${f#"$DATA"/}"
  local api="rpi-control-plane/${rel}"
  local extra="-no-encrypt"
  case "$rel" in
    */secrets/*|_cluster/credentials/*)
      extra="-encrypt"
      ;;
    _cluster/oidc/kubernetes-oidc.yaml|_cluster/oidc/kubeconfig-oidc.yaml)
      extra="-encrypt"
      ;;
  esac
  echo "apply $api ($extra)" >&2
  "$HUB" apply "$api" -f "$f" $extra >/dev/null
}

while IFS= read -r f; do
  apply_one "$f"
done < <(find "$DATA" -type f ! -name '.DS_Store' | sort)

# Retired after Headlamp migration
for stale in \
  rpi-control-plane/kubernetes-dashboard/config/configmaps.yaml \
  rpi-control-plane/kubernetes-dashboard/config/helmreleases.yaml \
  rpi-control-plane/kubernetes-dashboard/secrets/secrets.yaml \
  rpi-control-plane/kubernetes-dashboard/secrets/sealedsecrets.yaml \
  rpi-control-plane/_cluster/oidc/oauth2-proxy-helmrelease.yaml; do
  if "$HUB" get "$stale" -o json >/dev/null 2>&1; then
    echo "delete $stale" >&2
    "$HUB" delete "$stale" 0 >/dev/null 2>&1 || true
  fi
done

echo "Done → data/rpi-control-plane/ in sealhub-data"

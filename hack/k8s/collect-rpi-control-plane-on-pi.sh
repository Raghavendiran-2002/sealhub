#!/usr/bin/env bash
# Run ON rpi4-control-plane (pi@100.66.190.37): refresh /data/rpi-control-plane + cluster creds.
set -euo pipefail

ROOT="${RPI_BACKUP_ROOT:-/data/rpi-control-plane}"
REPO="${K8S_REPO:-$HOME/Kubernetes-Home-Lab}"
SUDO_PASS="${SUDO_PASS:-}"

sudo_cmd() {
  if [[ -n "$SUDO_PASS" ]]; then echo "$SUDO_PASS" | sudo -S "$@"; else sudo "$@"; fi
}

sudo_cmd mkdir -p "$ROOT"
if [[ -f "${REPO}/kubernetes/scripts/backup-rpi-control-plane.sh" ]]; then
  sudo_cmd env KUBECONFIG=/etc/kubernetes/admin.conf bash "${REPO}/kubernetes/scripts/backup-rpi-control-plane.sh"
else
  echo "Missing ${REPO}/kubernetes/scripts/backup-rpi-control-plane.sh" >&2
  exit 1
fi

CRED="${ROOT}/_cluster/credentials"
sudo_cmd mkdir -p "$CRED"
sudo_cmd chown pi:pi "$CRED"
if [[ -r /etc/kubernetes/admin.conf ]]; then
  sudo_cmd cp /etc/kubernetes/admin.conf "${CRED}/admin.conf"
  sudo_cmd chown pi:pi "${CRED}/admin.conf"
  chmod 600 "${CRED}/admin.conf"
fi
if [[ -f "${HOME}/.kube/config" ]]; then
  cp "${HOME}/.kube/config" "${CRED}/kubeconfig-pi.yaml"
  chmod 600 "${CRED}/kubeconfig-pi.yaml"
fi
if [[ -f /opt/homelab-private/kubernetes/sealed-secrets-key-backup.yaml ]]; then
  sudo_cmd cp /opt/homelab-private/kubernetes/sealed-secrets-key-backup.yaml "${CRED}/sealed-secrets-key-backup.yaml" 2>/dev/null || true
  sudo_cmd chown pi:pi "${CRED}/sealed-secrets-key-backup.yaml" 2>/dev/null || true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/collect-oidc-on-pi.sh" ]]; then
  bash "${SCRIPT_DIR}/collect-oidc-on-pi.sh"
fi

sudo_cmd chown -R pi:pi "$ROOT"
echo "Collected under ${ROOT}"

#!/usr/bin/env bash
# Store pi@rpi4-control-plane ~/.ssh/ed25519 key pair in SealHub (git: data/rpi-control-plane/ssh/...).
#
# From Mac:
#   source ~/.config/sealhub/env
#   ./hack/k8s/store-rpi-control-plane-ssh-to-sealhub.sh
#
# Optional: RPI_HOST RPI_USER RPI_PASS (password only if key auth fails)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RPI_HOST="${RPI_HOST:-100.66.190.37}"
RPI_USER="${RPI_USER:-pi}"
RPI_PASS="${RPI_PASS:-}"
PREFIX="${SEALHUB_SSH_PREFIX:-rpi-control-plane/ssh}"

export SEALHUB_SERVER="${SEALHUB_SERVER:-http://192.168.1.14:8080}"
HUB="${HUB:-$ROOT/bin/hub}"
[[ -x "$HUB" ]] || HUB="$(command -v hub)"
[[ -n "${SEALHUB_TOKEN:-}" ]] || { echo "Set SEALHUB_TOKEN" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=15)
remote() {
  if ssh "${SSH_OPTS[@]}" -o BatchMode=yes "${RPI_USER}@${RPI_HOST}" "$@" 2>/dev/null; then
    return 0
  fi
  [[ -n "$RPI_PASS" ]] || {
    echo "SSH to ${RPI_USER}@${RPI_HOST} failed; set RPI_PASS or configure key auth" >&2
    exit 1
  }
  command -v sshpass >/dev/null || { echo "sshpass required for password auth" >&2; exit 1; }
  sshpass -p "$RPI_PASS" ssh "${SSH_OPTS[@]}" "${RPI_USER}@${RPI_HOST}" "$@"
}

remote_scp() {
  local remote_path="$1" local_path="$2"
  if scp "${SSH_OPTS[@]}" -o BatchMode=yes "${RPI_USER}@${RPI_HOST}:${remote_path}" "$local_path" 2>/dev/null; then
    return 0
  fi
  sshpass -p "$RPI_PASS" scp "${SSH_OPTS[@]}" "${RPI_USER}@${RPI_HOST}:${remote_path}" "$local_path"
}

for f in id_ed25519 id_ed25519.pub; do
  remote_scp "~/.ssh/${f}" "${WORK}/${f}"
done

echo "apply ${PREFIX}/id_ed25519 (-encrypt)" >&2
"$HUB" apply "${PREFIX}/id_ed25519" -f "${WORK}/id_ed25519" -encrypt >/dev/null
echo "apply ${PREFIX}/id_ed25519.pub" >&2
"$HUB" apply "${PREFIX}/id_ed25519.pub" -f "${WORK}/id_ed25519.pub" >/dev/null

echo "Done → data/${PREFIX}/id_ed25519, data/${PREFIX}/id_ed25519.pub"

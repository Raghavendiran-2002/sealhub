#!/usr/bin/env bash
# From Mac: SSH to hostname live and run backup-pocket-id-on-live.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIVE_HOST="${LIVE_HOST:-100.114.97.68}"
LIVE_USER="${LIVE_USER:-pi}"
LIVE_PASS="${LIVE_PASS:-}"

TOKEN="${SEALHUB_TOKEN:-${SEALHUB_BOOTSTRAP_TOKEN:-pi-homelab-bootstrap-change-me}}"

SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=15)
remote() {
  if ssh "${SSH_OPTS[@]}" -o BatchMode=yes "${LIVE_USER}@${LIVE_HOST}" "$@" 2>/dev/null; then
    return 0
  fi
  [[ -n "$LIVE_PASS" ]] || {
    echo "SSH to ${LIVE_USER}@${LIVE_HOST} failed; set LIVE_PASS or use Tailscale/key auth" >&2
    exit 1
  }
  command -v sshpass >/dev/null || { echo "sshpass required for password auth" >&2; exit 1; }
  sshpass -p "$LIVE_PASS" ssh "${SSH_OPTS[@]}" "${LIVE_USER}@${LIVE_HOST}" "$@"
}

remote_scp() {
  local src="$1" dest="$2"
  if scp "${SSH_OPTS[@]}" -o BatchMode=yes "$src" "$dest" 2>/dev/null; then
    return 0
  fi
  sshpass -p "$LIVE_PASS" scp "${SSH_OPTS[@]}" "$src" "$dest"
}

remote_scp "${ROOT}/hack/pi/backup-pocket-id-on-live.sh" "${LIVE_USER}@${LIVE_HOST}:/tmp/backup-pocket-id-on-live.sh"
if [[ -f "${ROOT}/hack/pi/podman-compose/pocket-id/docker-compose.yaml" ]]; then
  remote "mkdir -p ~/pocket-id"
  remote_scp "${ROOT}/hack/pi/podman-compose/pocket-id/docker-compose.yaml" \
    "${LIVE_USER}@${LIVE_HOST}:~/pocket-id/docker-compose.yaml"
fi

SUDO_ENV=""
[[ -n "$LIVE_PASS" ]] && SUDO_ENV="SUDO_PASS='${LIVE_PASS}'"

remote "chmod +x /tmp/backup-pocket-id-on-live.sh; SEALHUB_TOKEN='${TOKEN}' SEALHUB_SERVER=http://127.0.0.1:8080 POCKET_BACKUP_STOP='${POCKET_BACKUP_STOP:-1}' ${SUDO_ENV} bash /tmp/backup-pocket-id-on-live.sh"

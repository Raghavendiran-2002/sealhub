#!/usr/bin/env bash
# Local or CI: pick latest snapshot from repo → SSH → restore on Pi.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ -n "${DEVICE_SSH:-}" ]]; then
  LIVE_USER="${DEVICE_SSH%%@*}"
  LIVE_HOST="${DEVICE_SSH#*@}"
else
  LIVE_HOST="${DEVICE_HOST:-${LIVE_HOST:-100.114.97.68}}"
  LIVE_USER="${DEVICE_USER:-${LIVE_USER:-pi}}"
fi
LIVE_PASS="${LIVE_PASS:-}"
DEFAULT_DATA="${SEALHUB_DATA_ROOT:-$ROOT/../sealhub-data}"
BACKUP_ROOT="${DEVICE_BACKUP_ROOT:-$DEFAULT_DATA/device-live}"
SNAP_ID="${1:-}"

DEVICE_SSH_OPTS=(
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=60
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=10
)
DEVICE_SSH_USER="$LIVE_USER"
DEVICE_SSH_PRIMARY_HOST="$LIVE_HOST"
DEVICE_SSH_HOST="$LIVE_HOST"
DEVICE_SSH_FALLBACK_HOST="${DEVICE_SSH_FALLBACK:-${PI_TAILSCALE_IP:-100.114.97.68}}"
# shellcheck source=lib/device-ssh.sh
source "$ROOT/hack/pi/lib/device-ssh.sh"
device_ssh_master_opts
trap device_ssh_close_master EXIT

if [[ -z "$SNAP_ID" ]]; then
  if [[ -f "${BACKUP_ROOT}/manifest.json" ]]; then
    SNAP_ID="$(python3 -c "import json; print(json.load(open('${BACKUP_ROOT}/manifest.json'))['snapshots'][0]['id'])")"
  else
    SNAP_ID="$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name '20*' | sort -r | head -1 | xargs basename)"
  fi
fi

[[ -n "$SNAP_ID" && -d "${BACKUP_ROOT}/${SNAP_ID}" ]] || {
  echo "no snapshot found under ${BACKUP_ROOT} (set SNAP_ID or run backup first)" >&2
  exit 1
}

log() { printf '==> %s\n' "$*"; }
log "restore ${SNAP_ID} → ${LIVE_USER}@${LIVE_HOST}"

device_ssh_remote "mkdir -p /tmp/sealhub-device-restore/lib"
device_ssh_push_file "${ROOT}/hack/pi/device-restore-on-pi.sh" /tmp/sealhub-device-restore/device-restore-on-pi.sh
device_ssh_push_file "${ROOT}/hack/pi/lib/podman-stacks.sh" /tmp/sealhub-device-restore/lib/podman-stacks.sh
device_ssh_remote "chmod +x /tmp/sealhub-device-restore/device-restore-on-pi.sh"

device_ssh_remote "rm -rf /tmp/sealhub-restore-${SNAP_ID} && mkdir -p /tmp/sealhub-restore-${SNAP_ID}"
device_ssh_push_dir "${BACKUP_ROOT}/${SNAP_ID}" "/tmp/sealhub-restore-${SNAP_ID}"

TOKEN="${SEALHUB_TOKEN:-}"
device_ssh_remote "chmod +x /tmp/sealhub-device-restore/*.sh; \
  SEALHUB_TOKEN='${TOKEN}' bash /tmp/sealhub-device-restore/device-restore-on-pi.sh /tmp/sealhub-restore-${SNAP_ID}"

log "restore finished"

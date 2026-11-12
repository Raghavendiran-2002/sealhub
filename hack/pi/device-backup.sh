#!/usr/bin/env bash
# Local or CI: SSH to Pi → snapshot → copy into repo → prune to 3 → optional git commit.
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
DATA_REPO="$(cd "$(dirname "$BACKUP_ROOT")" && pwd)"
BACKUP_DIR="$(basename "$BACKUP_ROOT")"
STAMP="$(date -u +%Y-%m-%dT%H%M%SZ)"
SNAP_ID="$STAMP"
GIT_COMMIT="${DEVICE_BACKUP_GIT_COMMIT:-1}"

DEVICE_SSH_OPTS=(
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=60
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=10
)
DEVICE_SSH_USER="$LIVE_USER"
DEVICE_SSH_HOST="$LIVE_HOST"
# shellcheck source=lib/device-ssh.sh
source "$ROOT/hack/pi/lib/device-ssh.sh"

log() { printf '==> %s\n' "$*"; }

log "device backup → ${BACKUP_ROOT}/${SNAP_ID} via ${LIVE_USER}@${LIVE_HOST}"

device_ssh_remote "mkdir -p /tmp/sealhub-device-backup/lib"
device_ssh_push_file "${ROOT}/hack/pi/device-snapshot-on-pi.sh" /tmp/sealhub-device-backup/device-snapshot-on-pi.sh
device_ssh_push_file "${ROOT}/hack/pi/lib/podman-stacks.sh" /tmp/sealhub-device-backup/lib/podman-stacks.sh
device_ssh_remote "chmod +x /tmp/sealhub-device-backup/device-snapshot-on-pi.sh"

TOKEN="${SEALHUB_TOKEN:-${SEALHUB_BOOTSTRAP_TOKEN:-}}"
SUDO_ENV=""
[[ -n "$LIVE_PASS" ]] && SUDO_ENV="SUDO_PASS='${LIVE_PASS}'"

device_ssh_remote "rm -rf /tmp/sealhub-snap-${SNAP_ID} && mkdir -p /tmp/sealhub-snap-${SNAP_ID}"
device_ssh_remote "chmod +x /tmp/sealhub-device-backup/*.sh; \
  SEALHUB_TOKEN='${TOKEN}' SEALHUB_SERVER=http://127.0.0.1:8080 ${SUDO_ENV} \
  bash /tmp/sealhub-device-backup/device-snapshot-on-pi.sh /tmp/sealhub-snap-${SNAP_ID}"

mkdir -p "${BACKUP_ROOT}/${SNAP_ID}"
# Brief pause after snapshot trap restarts stacks before opening a new SSH/scp session.
sleep 3
device_ssh_pull_dir "/tmp/sealhub-snap-${SNAP_ID}" "${BACKUP_ROOT}/${SNAP_ID}"
device_ssh_remote "rm -rf /tmp/sealhub-snap-${SNAP_ID}"

bash "$ROOT/hack/pi/prune-device-backups.sh" "$BACKUP_ROOT"

if [[ "$GIT_COMMIT" == "1" ]] && git -C "$DATA_REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$DATA_REPO" add "$BACKUP_DIR/"
  if ! git -C "$DATA_REPO" diff --staged --quiet; then
    git -C "$DATA_REPO" commit -m "chore(backup): device-live ${SNAP_ID}"
    log "committed in sealhub-data (push separately or via GitHub Actions)"
  fi
fi

log "done — snapshot ${SNAP_ID}"

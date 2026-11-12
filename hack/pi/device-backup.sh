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
BACKUP_ROOT="${DEVICE_BACKUP_ROOT:-$ROOT/backups/device-live}"
STAMP="$(date -u +%Y-%m-%dT%H%M%SZ)"
SNAP_ID="$STAMP"
GIT_COMMIT="${DEVICE_BACKUP_GIT_COMMIT:-1}"

SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=20)

remote() {
  if ssh "${SSH_OPTS[@]}" -o BatchMode=yes "${LIVE_USER}@${LIVE_HOST}" "$@" 2>/dev/null; then
    return 0
  fi
  [[ -n "$LIVE_PASS" ]] || die_ssh
  command -v sshpass >/dev/null || { echo "sshpass required" >&2; exit 1; }
  sshpass -p "$LIVE_PASS" ssh "${SSH_OPTS[@]}" "${LIVE_USER}@${LIVE_HOST}" "$@"
}

remote_scp() {
  local src="$1" dest="$2"
  if scp "${SSH_OPTS[@]}" -o BatchMode=yes -r "$src" "$dest" 2>/dev/null; then
    return 0
  fi
  sshpass -p "$LIVE_PASS" scp "${SSH_OPTS[@]}" -r "$src" "$dest"
}

die_ssh() {
  echo "SSH to ${LIVE_USER}@${LIVE_HOST} failed (BatchMode). Use Tailscale, SSH keys, or LIVE_PASS." >&2
  exit 1
}

log() { printf '==> %s\n' "$*"; }

log "device backup → ${BACKUP_ROOT}/${SNAP_ID} via ${LIVE_USER}@${LIVE_HOST}"

remote "mkdir -p /tmp/sealhub-device-backup/lib"
for f in device-snapshot-on-pi.sh; do
  scp "${SSH_OPTS[@]}" -o BatchMode=yes "${ROOT}/hack/pi/$f" \
    "${LIVE_USER}@${LIVE_HOST}:/tmp/sealhub-device-backup/" 2>/dev/null \
    || sshpass -p "$LIVE_PASS" scp "${SSH_OPTS[@]}" "${ROOT}/hack/pi/$f" \
      "${LIVE_USER}@${LIVE_HOST}:/tmp/sealhub-device-backup/"
done
scp "${SSH_OPTS[@]}" -o BatchMode=yes "${ROOT}/hack/pi/lib/podman-stacks.sh" \
  "${LIVE_USER}@${LIVE_HOST}:/tmp/sealhub-device-backup/lib/" 2>/dev/null \
  || sshpass -p "$LIVE_PASS" scp "${SSH_OPTS[@]}" "${ROOT}/hack/pi/lib/podman-stacks.sh" \
    "${LIVE_USER}@${LIVE_HOST}:/tmp/sealhub-device-backup/lib/"

TOKEN="${SEALHUB_TOKEN:-${SEALHUB_BOOTSTRAP_TOKEN:-}}"
SUDO_ENV=""
[[ -n "$LIVE_PASS" ]] && SUDO_ENV="SUDO_PASS='${LIVE_PASS}'"

remote "rm -rf /tmp/sealhub-snap-${SNAP_ID} && mkdir -p /tmp/sealhub-snap-${SNAP_ID}"
remote "chmod +x /tmp/sealhub-device-backup/*.sh; \
  SEALHUB_TOKEN='${TOKEN}' SEALHUB_SERVER=http://127.0.0.1:8080 ${SUDO_ENV} \
  bash /tmp/sealhub-device-backup/device-snapshot-on-pi.sh /tmp/sealhub-snap-${SNAP_ID}"

mkdir -p "${BACKUP_ROOT}/${SNAP_ID}"
remote_scp "${LIVE_USER}@${LIVE_HOST}:/tmp/sealhub-snap-${SNAP_ID}/*" "${BACKUP_ROOT}/${SNAP_ID}/"
remote "rm -rf /tmp/sealhub-snap-${SNAP_ID}"

bash "$ROOT/hack/pi/prune-device-backups.sh" "$BACKUP_ROOT"

if [[ "$GIT_COMMIT" == "1" ]] && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$ROOT" add "backups/device-live/"
  if ! git -C "$ROOT" diff --staged --quiet; then
    git -C "$ROOT" commit -m "chore(backup): device-live ${SNAP_ID}"
    log "committed locally (push separately or via GitHub Actions)"
  fi
fi

log "done — snapshot ${SNAP_ID}"

#!/usr/bin/env bash
# Run ON the Pi: stop stacks, restore from snapshot dir, restart.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/podman-stacks.sh
source "$SCRIPT_DIR/lib/podman-stacks.sh" 2>/dev/null || source /tmp/sealhub-device-restore/lib/podman-stacks.sh

SNAP_DIR="${1:?usage: device-restore-on-pi.sh /path/to/snapshot-dir}"
SEALHUB_REPO="${SEALHUB_REPO:-/var/lib/sealhub/repo}"
POCKET_ID_HOME="${POCKET_ID_HOME:-$HOME/pocket-id}"

[[ -f "$SNAP_DIR/metadata.json" ]] || { echo "missing metadata.json in $SNAP_DIR" >&2; exit 1; }

stop_all_stacks

if [[ -f "$SNAP_DIR/sealhub-repo.tar.gz" ]]; then
  echo "restoring sealhub-data working copy..." >&2
  rm -rf "${SEALHUB_REPO}.bak"
  mv "$SEALHUB_REPO" "${SEALHUB_REPO}.bak" 2>/dev/null || true
  tar -xzf "$SNAP_DIR/sealhub-repo.tar.gz" -C "$(dirname "$SEALHUB_REPO")"
fi

if [[ -f "$SNAP_DIR/pocket-id-home.tar.gz" ]]; then
  echo "restoring pocket-id home..." >&2
  rm -rf "${POCKET_ID_HOME}.bak"
  mv "$POCKET_ID_HOME" "${POCKET_ID_HOME}.bak" 2>/dev/null || true
  tar -xzf "$SNAP_DIR/pocket-id-home.tar.gz" -C "$(dirname "$POCKET_ID_HOME")"
fi

if [[ -f "$SNAP_DIR/etc-sealhub/config.yaml" ]]; then
  echo "restoring /etc/sealhub/config.yaml (sudo)..." >&2
  sudo mkdir -p /etc/sealhub
  sudo cp "$SNAP_DIR/etc-sealhub/config.yaml" /etc/sealhub/config.yaml
fi

export FORCE_START_HUBD=1
export FORCE_START_POCKET=1
start_all_stacks

if [[ -n "${SEALHUB_TOKEN:-}" ]] && command -v hub >/dev/null; then
  sleep 3
  if curl -sf http://127.0.0.1:8080/healthz >/dev/null 2>&1; then
    hub pocket restore -dir "$POCKET_ID_HOME" -no-stop 2>/dev/null || true
  fi
fi

echo "restore complete from $SNAP_DIR" >&2

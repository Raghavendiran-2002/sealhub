#!/usr/bin/env bash
# Run ON live (or via ssh pi@live bash -s < hack/pi/backup-live-snapshot.sh):
# Pocket ID snapshot + SSH keys + optional RootOS compose paths into sealhub-data.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=homelab-env.sh
source "$ROOT/hack/pi/homelab-env.sh"

export SEALHUB_SERVER="${SEALHUB_SERVER:-$SEALHUB_SERVER_LOCAL}"
[[ -n "${SEALHUB_TOKEN:-}" ]] || {
  echo "Set SEALHUB_TOKEN (bootstrap token or ~/.config/sealhub/env)" >&2
  exit 1
}

echo "==> Pocket ID + homelab secrets" >&2
POCKET_BACKUP_STOP="${POCKET_BACKUP_STOP:-1}" "$ROOT/hack/pi/backup-pocket-id-on-live.sh"

echo "==> live/ssh (+ tailscale if present)" >&2
"$ROOT/hack/pi/store-pi-ssh-tailscale.sh"

POCKET_DIR="${POCKET_ID_HOME:-$HOME/pocket-id}"
if [[ -f "${POCKET_DIR}/starry/config.yml" ]]; then
  echo "==> RootOS dashboard config" >&2
  hub apply live/starry-cloud/config.yml -f "${POCKET_DIR}/starry/config.yml" -no-encrypt
fi
if [[ -f "${POCKET_DIR}/starry/auth.yml" ]]; then
  hub apply live/starry-cloud/auth.yml -f "${POCKET_DIR}/starry/auth.yml" -encrypt
fi
if [[ -f "${POCKET_DIR}/docker-compose.yaml" ]]; then
  hub apply live/podman-compose/pocket-id/docker-compose.yaml -f "${POCKET_DIR}/docker-compose.yaml" -no-encrypt
fi

echo "Live snapshot complete (hubd → sealhub-data git)." >&2

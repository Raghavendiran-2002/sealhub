#!/usr/bin/env bash
# Start Pocket ID with podman (no compose plugin required).
# Upstream image: amd64/arm64 only — not armv7.
set -euo pipefail

POCKET_ID_IMAGE="${POCKET_ID_IMAGE:-ghcr.io/pocket-id/pocket-id:v2.14.0}"

if [[ "$(uname -m)" == "armv7l" ]]; then
  echo "Pocket ID upstream image has no linux/arm/v7 build; use arm64 Pi OS or run Pocket ID elsewhere." >&2
  echo "Data restore still works: hub pocket restore -dir \$HOME/pocket-id" >&2
  exit 1
fi

HOME_DIR="${POCKET_ID_HOME:-$HOME/pocket-id}"
cd "$HOME_DIR"

if [[ ! -f .env ]] || [[ ! -f data/pocket-id.db ]]; then
  echo "missing .env or data/pocket-id.db — run: hub pocket restore -dir $HOME_DIR" >&2
  exit 1
fi

podman rm -f pocket-id 2>/dev/null || true
podman run -d --name pocket-id \
  --replace \
  -p 1411:1411 \
  --env-file .env \
  -e "DB_CONNECTION_STRING=file:data/pocket-id.db?_journal_mode=DELETE" \
  -v "$HOME_DIR/data:/app/data:Z" \
  "$POCKET_ID_IMAGE"

echo "Pocket ID → http://$(hostname -I | awk '{print $1}'):1411"

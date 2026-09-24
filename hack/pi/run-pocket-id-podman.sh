#!/usr/bin/env bash
# Start Pocket ID with podman (no compose plugin required).
# Requires 64-bit OS (aarch64/amd64): upstream image has no arm/v7 build.
set -euo pipefail

POCKET_ID_IMAGE="${POCKET_ID_IMAGE:-ghcr.io/raghavendiran-2002/sealhub/pocket-id:armv7-latest}"

if [[ "$(uname -m)" == "armv7l" ]]; then
  echo "Using SealHub armv7 image: $POCKET_ID_IMAGE" >&2
  echo "Build via Actions → Pocket ID armv7 image (see docs/POCKET-ID-ARMV7.md)" >&2
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

#!/usr/bin/env bash
# Push Pocket ID + Cloudflare homelab secrets into sealhub-data (API: live/... → git data/live/...).
#
# Usage (Mac, hubd reachable):
#   source ~/.config/sealhub/env
#   POCKET_ID_HOME=/path/to/pocket-id ./hack/local/store-pocket-live.sh
#
# TUNNEL_TOKEN from .env → live/cloudflare/token.txt (Cloudflare tunnel connector token).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
POCKET_ID_HOME="${POCKET_ID_HOME:-/Users/raghavendiran/Desktop/Home-Lab/Pocket_ID_Mac/pocket-id}"
ENV_FILE="${POCKET_ID_HOME}/.env"
DB_FILE="${POCKET_ID_HOME}/data/pocket-id.db"

export SEALHUB_SERVER="${SEALHUB_SERVER:-http://192.168.1.14:8080}"
if [[ -z "${SEALHUB_TOKEN:-}" ]]; then
  echo "Set SEALHUB_TOKEN (bootstrap or scoped token)" >&2
  exit 1
fi

HUB="${HUB:-$ROOT/bin/hub}"
if [[ ! -x "$HUB" ]]; then
  HUB="$(command -v hub || true)"
fi
[[ -n "$HUB" && -x "$HUB" ]] || { echo "hub not found; build with: (cd $ROOT && go build -o bin/hub ./cmd/hub)" >&2; exit 1; }

apply_file() {
  local api_path="$1"
  local src="$2"
  shift 2
  echo "apply $api_path <- $src" >&2
  "$HUB" apply "$api_path" -f "$src" "$@" >/dev/null
}

if [[ ! -f "$ENV_FILE" ]]; then
  echo "missing $ENV_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

if [[ -z "${TUNNEL_TOKEN:-}" ]]; then
  echo "TUNNEL_TOKEN missing in $ENV_FILE" >&2
  exit 1
fi
printf '%s\n' "$TUNNEL_TOKEN" >"$tmp"
apply_file "live/cloudflare/token.txt" "$tmp" "-encrypt"

if [[ -z "${ENCRYPTION_KEY:-}" ]]; then
  echo "ENCRYPTION_KEY missing in $ENV_FILE" >&2
  exit 1
fi
printf '%s\n' "$ENCRYPTION_KEY" >"$tmp"
apply_file "live/pocket-id/encryption.key" "$tmp" "-encrypt"

if [[ ! -f "$DB_FILE" ]]; then
  echo "missing $DB_FILE" >&2
  exit 1
fi
apply_file "live/pocket-id/db" "$DB_FILE" "-encrypt"

echo "Done. Git paths: data/live/cloudflare/, data/live/pocket-id/"

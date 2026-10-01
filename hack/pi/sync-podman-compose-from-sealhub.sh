#!/usr/bin/env bash
# Restore live/podman-compose/* from hubd into ~/podman-compose/ (run on Pi).
set -euo pipefail

DEST="${PODMAN_COMPOSE_HOME:-$HOME/podman-compose}"
export SEALHUB_SERVER="${SEALHUB_SERVER:-http://127.0.0.1:8080}"

command -v hub >/dev/null || { echo "source ~/.config/sealhub/env" >&2; exit 1; }
command -v jq >/dev/null || { echo "install jq" >&2; exit 1; }

fetch() {
  local api_path="$1"
  local out="$2"
  mkdir -p "$(dirname "$out")"
  hub get "$api_path" -o json | jq -r '.Document' >"$out"
}

list_paths() {
  hub list live/podman-compose/ -o json | jq -r '.[].path' | sed 's|^live/podman-compose/||'
}

while IFS= read -r rel; do
  [[ -n "$rel" ]] || continue
  case "$rel" in
    dnsmasq/*) continue ;;
  esac
  fetch "live/podman-compose/$rel" "$DEST/$rel"
done < <(list_paths)

if [[ -f "$DEST/pocket-id/docker-compose.yaml" && -d "$HOME/pocket-id" ]]; then
  cp "$DEST/pocket-id/docker-compose.yaml" "$HOME/pocket-id/docker-compose.yaml"
  echo "Updated ~/pocket-id/docker-compose.yaml"
fi
if [[ -f "$DEST/pocket-id/starry/config.yml" && -d "$HOME/pocket-id" ]]; then
  mkdir -p "$HOME/pocket-id/starry"
  cp "$DEST/pocket-id/starry/config.yml" "$HOME/pocket-id/starry/config.yml"
  chmod 644 "$HOME/pocket-id/starry/config.yml"
  echo "Updated ~/pocket-id/starry/config.yml"
fi
if hub get live/starry-cloud/auth.yml -o json >/dev/null 2>&1 && [[ -d "$HOME/pocket-id" ]]; then
  mkdir -p "$HOME/pocket-id/starry"
  fetch "live/starry-cloud/auth.yml" "$HOME/pocket-id/starry/auth.yml"
  chmod 644 "$HOME/pocket-id/starry/auth.yml"
  echo "Updated ~/pocket-id/starry/auth.yml from live/starry-cloud/auth.yml"
fi

echo "Synced to $DEST"

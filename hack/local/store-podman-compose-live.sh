#!/usr/bin/env bash
# Upload hack/pi/podman-compose/* to sealhub-data (data/live/podman-compose/...).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$ROOT/hack/pi/podman-compose"

export SEALHUB_SERVER="${SEALHUB_SERVER:-http://192.168.1.14:8080}"
HUB="${HUB:-$ROOT/bin/hub}"
[[ -x "$HUB" ]] || HUB="$(command -v hub)"
[[ -n "${SEALHUB_TOKEN:-}" ]] || { echo "Set SEALHUB_TOKEN" >&2; exit 1; }

apply() {
  local rel="$1"
  local f="$SRC/$rel"
  [[ -f "$f" ]] || { echo "missing $f" >&2; exit 1; }
  echo "apply live/podman-compose/$rel" >&2
  "$HUB" apply "live/podman-compose/$rel" -f "$f" -no-encrypt >/dev/null
}

while IFS= read -r f; do
  rel="${f#"$SRC"/}"
  case "$rel" in
    README.md) continue ;;
    dnsmasq/*) continue ;;
  esac
  apply "$rel"
done < <(find "$SRC" -type f \( -name '*.yaml' -o -name '*.yml' -o -name '.env.example' \) | sort)

# Remove retired dnsmasq docs from git via hubd
for path in \
  live/podman-compose/dnsmasq/docker-compose.yaml \
  live/podman-compose/dnsmasq/dnsmasq.conf; do
  if "$HUB" get "$path" -o json >/dev/null 2>&1; then
    echo "delete $path" >&2
    "$HUB" delete "$path" 0 >/dev/null 2>&1 || "$HUB" delete "$path" >/dev/null 2>&1 || true
  fi
done

echo "Done → data/live/podman-compose/ in sealhub-data"

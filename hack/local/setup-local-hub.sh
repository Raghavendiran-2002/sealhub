#!/usr/bin/env bash
# Build hub CLI and prepare local env pointing at Pi hubd.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

mkdir -p bin
echo "Building hub → bin/hub ..."
go build -o bin/hub ./cmd/hub

SHARED_INSTALL="$ROOT/hack/shared/install-hub-cli.sh"
EXAMPLE="$ROOT/hack/local/sealhub.env.example"
ENV_FILE="$ROOT/hack/local/sealhub.env"
USER_ENV="${HOME}/.config/sealhub/env"

chmod +x "$SHARED_INSTALL"
"$SHARED_INSTALL" "$ROOT/bin/hub" "$EXAMPLE"

if [[ ! -f "$ENV_FILE" ]]; then
  ln -sf "$USER_ENV" "$ENV_FILE" 2>/dev/null || cp "$USER_ENV" "$ENV_FILE"
fi

# shellcheck disable=SC1090
source "$USER_ENV"

if curl -sf "${SEALHUB_SERVER}/healthz" >/dev/null; then
  echo "hubd reachable at $SEALHUB_SERVER"
else
  echo "Warning: cannot reach $SEALHUB_SERVER (Tailscale / LAN?)"
fi

echo ""
echo "hub is on PATH (~/.local/bin/hub). Env: ~/.config/sealhub/env"
echo "  source ~/.config/sealhub/env   # or: source hack/local/sealhub.env"
echo ""
echo "Try:"
echo "  hub get config/homelab/settings.yaml"
echo "  hub list secrets/homelab"

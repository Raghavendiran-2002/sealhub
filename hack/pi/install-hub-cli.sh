#!/usr/bin/env bash
# On Pi: install hub from a built binary or cross-compile locally.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_EXAMPLE="$ROOT/hack/pi/sealhub.env.example"
SHARED="$ROOT/hack/shared/install-hub-cli.sh"

if [[ ! -x "$SHARED" ]]; then
  echo "missing $SHARED" >&2
  exit 1
fi

if [[ -n "${1:-}" ]]; then
  HUB_BIN="$1"
else
  echo "Building hub for $(uname -m) ..."
  mkdir -p "$ROOT/bin"
  case "$(uname -m)" in
    armv7l) export GOARM=7 ;;
  esac
  (cd "$ROOT" && go build -o "$ROOT/bin/hub" ./cmd/hub)
  HUB_BIN="$ROOT/bin/hub"
fi

chmod +x "$SHARED"
"$SHARED" "$HUB_BIN" "$ENV_EXAMPLE"

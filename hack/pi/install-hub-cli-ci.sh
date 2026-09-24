#!/usr/bin/env bash
# Called from GitHub Actions: install-hub-cli-ci.sh /tmp/sealhub-hub /tmp/install-hub-cli.sh /tmp/sealhub.env.example
set -euo pipefail

HUB_TMP="${1:?hub binary}"
INSTALLER="${2:?install-hub-cli.sh path}"
ENV_EXAMPLE="${3:?env example path}"

chmod +x "$INSTALLER" "$HUB_TMP"
"$INSTALLER" "$HUB_TMP" "$ENV_EXAMPLE"

export PATH="$HOME/.local/bin:$PATH"
# shellcheck disable=SC1091
source "$HOME/.config/sealhub/env"
curl -sf "${SEALHUB_SERVER}/healthz" >/dev/null
hub list config/homelab >/dev/null
echo "hub CLI ok — $(command -v hub)"

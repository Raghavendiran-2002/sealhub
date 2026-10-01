#!/usr/bin/env bash
# Install Starry Cloud on live and push configs to SealHub (live/starry-cloud/*).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIVE_HOST="${LIVE_HOST:-100.114.97.68}"
LIVE_USER="${LIVE_USER:-pi}"

SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=15)
remote() {
  ssh "${SSH_OPTS[@]}" -o BatchMode=yes "${LIVE_USER}@${LIVE_HOST}" "$@"
}

remote_scp() {
  scp "${SSH_OPTS[@]}" -o BatchMode=yes -r "$@"
}

[[ -n "${STARRY_OIDC_CLIENT_SECRET:-}" ]] || { echo "Set STARRY_OIDC_CLIENT_SECRET" >&2; exit 1; }

export STARRY_OIDC_CLIENT_ID="${STARRY_OIDC_CLIENT_ID:-78d8baad-cca1-44d6-9257-71a3c439d85e}"
export STARRY_OIDC_DISCOVERY_URL="${STARRY_OIDC_DISCOVERY_URL:-https://id.raghavendiran.cloud/.well-known/openid-configuration}"
export STARRY_OIDC_PROVIDER_NAME="${STARRY_OIDC_PROVIDER_NAME:-Pocket ID}"
export STARRY_OIDC_SCOPE="${STARRY_OIDC_SCOPE:-openid email profile groups}"

remote "mkdir -p ~/sealhub/hack/pi/starry-cloud"
remote_scp "${ROOT}/hack/pi/starry-cloud" "${LIVE_USER}@${LIVE_HOST}:~/sealhub/hack/pi/"
remote_scp "${ROOT}/hack/pi/install-starry-cloud-on-live.sh" "${LIVE_USER}@${LIVE_HOST}:~/install-starry-cloud-on-live.sh"

remote "chmod +x ~/install-starry-cloud-on-live.sh; \
  STARRY_OIDC_CLIENT_ID='${STARRY_OIDC_CLIENT_ID}' \
  STARRY_OIDC_CLIENT_SECRET='${STARRY_OIDC_CLIENT_SECRET}' \
  STARRY_OIDC_DISCOVERY_URL='${STARRY_OIDC_DISCOVERY_URL}' \
  STARRY_OIDC_PROVIDER_NAME='${STARRY_OIDC_PROVIDER_NAME}' \
  STARRY_OIDC_SCOPE='${STARRY_OIDC_SCOPE}' \
  INSTALL_DIR=\$HOME/starry-cloud \
  SEALHUB_HACK=\$HOME/sealhub/hack/pi/starry-cloud \
  bash ~/install-starry-cloud-on-live.sh"

export SEALHUB_SERVER="${SEALHUB_SERVER:-http://192.168.1.14:8080}"
[[ -n "${SEALHUB_TOKEN:-}" ]] || { echo "Set SEALHUB_TOKEN for SealHub store" >&2; exit 1; }
HUB="${HUB:-$ROOT/bin/hub}"
[[ -x "$HUB" ]] || HUB="$(command -v hub)"

remote_scp "${LIVE_USER}@${LIVE_HOST}:~/starry-cloud/config.yml" /tmp/starry-config.yml
remote_scp "${LIVE_USER}@${LIVE_HOST}:~/starry-cloud/auth.yml" /tmp/starry-auth.yml
remote_scp "${LIVE_USER}@${LIVE_HOST}:~/starry-cloud/docker-compose.yml" /tmp/starry-compose.yml

"$HUB" apply live/starry-cloud/config.yml -f /tmp/starry-config.yml >/dev/null
"$HUB" apply live/starry-cloud/docker-compose.yml -f /tmp/starry-compose.yml >/dev/null
"$HUB" apply live/starry-cloud/auth.yml -f /tmp/starry-auth.yml -encrypt >/dev/null
rm -f /tmp/starry-config.yml /tmp/starry-auth.yml /tmp/starry-compose.yml

echo "Starry Cloud: http://${LIVE_HOST}:5000 (LAN) — OIDC callback: https://home.raghavendiran.cloud/login/oidc/callback"
echo "SealHub: live/starry-cloud/{config.yml,docker-compose.yml,auth.yml}"

#!/usr/bin/env bash
# Build starry-cloud (arm64), load on live, configure Pocket ID OIDC, start via SSH.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIVE_HOST="${LIVE_HOST:-100.114.97.68}"
LIVE_USER="${LIVE_USER:-pi}"
INSTALL_DIR="${STARRY_CLOUD_HOME:-/home/pi/starry-cloud}"
IMAGE="${STARRY_CLOUD_IMAGE:-starry-cloud:local}"
BUILD_DIR="${TMPDIR:-/tmp}/starry-cloud-src-$$"

trap 'rm -rf "$BUILD_DIR"' EXIT

[[ -n "${STARRY_OIDC_CLIENT_SECRET:-}" ]] || { echo "Set STARRY_OIDC_CLIENT_SECRET" >&2; exit 1; }
export STARRY_OIDC_CLIENT_ID="${STARRY_OIDC_CLIENT_ID:-78d8baad-cca1-44d6-9257-71a3c439d85e}"
export STARRY_OIDC_DISCOVERY_URL="${STARRY_OIDC_DISCOVERY_URL:-https://id.raghavendiran.cloud/.well-known/openid-configuration}"
export STARRY_OIDC_PROVIDER_NAME="${STARRY_OIDC_PROVIDER_NAME:-Pocket ID}"
export STARRY_OIDC_SCOPE="${STARRY_OIDC_SCOPE:-openid email profile groups}"

SSH=(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=30 "${LIVE_USER}@${LIVE_HOST}")
SCP=(scp -o BatchMode=yes -o StrictHostKeyChecking=accept-new)

if ! "${SSH[@]}" "podman image exists ${IMAGE} 2>/dev/null"; then
  echo "==> Build ${IMAGE} on Mac and load on Pi..." >&2
  git clone --depth 1 https://github.com/starry-shivam/starry-cloud.git "$BUILD_DIR"
  cp "$ROOT/hack/pi/starry-cloud/config.yml" "$BUILD_DIR/config.yml"
  (cd "$BUILD_DIR" && docker build --platform linux/arm64 -t "$IMAGE" .)
  docker save "$IMAGE" | gzip | "${SSH[@]}" 'gunzip | podman load'
fi

"${SSH[@]}" "mkdir -p ${INSTALL_DIR} ~/sealhub/hack/pi"
"${SCP[@]}" -r "$ROOT/hack/pi/starry-cloud" "${LIVE_USER}@${LIVE_HOST}:~/sealhub/hack/pi/"
"${SCP[@]}" "$ROOT/hack/pi/starry-cloud/config.yml" "$ROOT/hack/pi/starry-cloud/docker-compose.yml" \
  "${LIVE_USER}@${LIVE_HOST}:${INSTALL_DIR}/"

SECRET=$(openssl rand -base64 48 | tr -d '\n')
GEN=$("${SSH[@]}" "printf '\n\n\n' | podman run -i --rm ${IMAGE} gen-auth --password 'disabled-login' --secret-key '${SECRET}'" \
  | sed -n '/^auth:/,$p')

AUTH_FILE=$(mktemp)
python3 - "$GEN" "$AUTH_FILE" <<'PY'
import os, sys
gen = sys.argv[1].strip().splitlines()
out = list(gen)
out.extend([
  "  password_enabled: false",
  "  oidc:",
  "    enabled: true",
  f'    provider_name: "{os.environ["STARRY_OIDC_PROVIDER_NAME"]}"',
  f'    discovery_url: "{os.environ["STARRY_OIDC_DISCOVERY_URL"]}"',
  f'    client_id: "{os.environ["STARRY_OIDC_CLIENT_ID"]}"',
  f'    client_secret: "{os.environ["STARRY_OIDC_CLIENT_SECRET"]}"',
  f'    scope: "{os.environ["STARRY_OIDC_SCOPE"]}"',
  "    allowed_emails: []",
])
open(sys.argv[2], "w").write("\n".join(out) + "\n")
PY
"${SCP[@]}" "$AUTH_FILE" "${LIVE_USER}@${LIVE_HOST}:${INSTALL_DIR}/auth.yml"
rm -f "$AUTH_FILE"

"${SSH[@]}" "chmod 644 ${INSTALL_DIR}/auth.yml ${INSTALL_DIR}/config.yml; cd ${INSTALL_DIR} && podman compose up -d --force-recreate; curl -sf http://127.0.0.1:5000/health"

if [[ -n "${SEALHUB_TOKEN:-}" ]]; then
  export SEALHUB_SERVER="${SEALHUB_SERVER:-http://192.168.1.14:8080}"
  HUB="${HUB:-$ROOT/bin/hub}"; [[ -x "$HUB" ]] || HUB="$(command -v hub)"
  for f in config.yml docker-compose.yml auth.yml; do
    "${SCP[@]}" "${LIVE_USER}@${LIVE_HOST}:${INSTALL_DIR}/${f}" "/tmp/starry-${f}"
    extra=(); [[ "$f" == auth.yml ]] && extra=(-encrypt)
    "$HUB" apply "live/starry-cloud/${f}" -f "/tmp/starry-${f}" "${extra[@]}" >/dev/null
    rm -f "/tmp/starry-${f}"
  done
fi

echo "Running: http://192.168.1.14:5000 — register OIDC callback https://home.raghavendiran.cloud/login/oidc/callback"

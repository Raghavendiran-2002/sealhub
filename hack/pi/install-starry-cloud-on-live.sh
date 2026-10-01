#!/usr/bin/env bash
# Run on hostname live: clone/build Starry Cloud, apply auth from env, start podman compose.
set -euo pipefail

REPO="${STARRY_CLOUD_REPO:-https://github.com/starry-shivam/starry-cloud.git}"
INSTALL_DIR="${STARRY_CLOUD_HOME:-$HOME/starry-cloud}"
HACK_DIR="${SEALHUB_HACK:-$HOME/sealhub/hack/pi/starry-cloud}"

mkdir -p "$(dirname "$INSTALL_DIR")"
if [[ ! -d "$INSTALL_DIR/.git" ]]; then
  git clone --depth 1 "$REPO" "$INSTALL_DIR"
fi

cp "$HACK_DIR/config.yml" "$INSTALL_DIR/config.yml"
cp "$HACK_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"

if [[ ! -f "$INSTALL_DIR/auth.yml" ]]; then
  cp "$INSTALL_DIR/auth.example.yml" "$INSTALL_DIR/auth.yml"
fi

echo "Building starry-cloud image (first build can take 15–30 min on Pi)..." >&2
(cd "$INSTALL_DIR" && podman compose build)

echo "Generating signing keys (gen-auth)..." >&2
(cd "$INSTALL_DIR" && podman compose run --rm starry-cloud gen-auth) >"$INSTALL_DIR/auth.yml"

export INSTALL_DIR
export STARRY_OIDC_PROVIDER_NAME="${STARRY_OIDC_PROVIDER_NAME:-Pocket ID}"
export STARRY_OIDC_SCOPE="${STARRY_OIDC_SCOPE:-openid email profile groups}"
python3 - <<'PY'
import os, re, pathlib, sys
for k in ("STARRY_OIDC_DISCOVERY_URL", "STARRY_OIDC_CLIENT_ID", "STARRY_OIDC_CLIENT_SECRET"):
    if not os.environ.get(k):
        sys.exit(f"missing {k}")
p = pathlib.Path(os.environ["INSTALL_DIR"]) / "auth.yml"
text = p.read_text()
replacements = [
    (r"password_enabled:\s*\w+", "password_enabled: false"),
    (r"(\s+oidc:\s*\n\s*)enabled:\s*false", r"\1enabled: true"),
    (r'provider_name:\s*"[^"]*"', f'provider_name: "{os.environ.get("STARRY_OIDC_PROVIDER_NAME", "Pocket ID")}"'),
    (r'discovery_url:\s*"[^"]*"', f'discovery_url: "{os.environ["STARRY_OIDC_DISCOVERY_URL"]}"'),
    (r'client_id:\s*"[^"]*"', f'client_id: "{os.environ["STARRY_OIDC_CLIENT_ID"]}"'),
    (r'client_secret:\s*"[^"]*"', f'client_secret: "{os.environ["STARRY_OIDC_CLIENT_SECRET"]}"'),
    (r'scope:\s*"[^"]*"', f'scope: "{os.environ.get("STARRY_OIDC_SCOPE", "openid email profile groups")}"'),
]
for pat, val in replacements:
    text, n = re.subn(pat, val, text, count=1)
    if n == 0:
        sys.exit(f"auth.yml patch failed: {pat}")
p.write_text(text)
print("auth.yml OIDC updated", file=sys.stderr)
PY

chmod 600 "$INSTALL_DIR/auth.yml" "$INSTALL_DIR/config.yml"

echo "Starting starry-cloud..." >&2
(cd "$INSTALL_DIR" && podman compose up -d)

podman ps --filter name=starry-cloud --format '{{.Names}} {{.Status}}'

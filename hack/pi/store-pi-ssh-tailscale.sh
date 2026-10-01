#!/usr/bin/env bash
# Run on the Pi (or via: ssh pi@live 'bash -s' < hack/pi/store-pi-ssh-tailscale.sh)
# Stores ~/.ssh key pair and tailscale config in SealHub under data/live/ (API: live/...).
set -euo pipefail

HOSTNAME_SHORT="${PI_HOSTNAME:-$(hostname -s)}"
if [[ "$HOSTNAME_SHORT" != "live" ]]; then
  echo "warning: PI_HOSTNAME=$HOSTNAME_SHORT; paths use live/ prefix (data/live/ in git)" >&2
fi

SSH_DIR="${HOME}/.ssh"
TS_CONFIG="${TAILSCALE_CONFIG_FILE:-/etc/tailscale/config.json}"

export SEALHUB_SERVER="${SEALHUB_SERVER:-http://127.0.0.1:8080}"
if [[ -z "${SEALHUB_TOKEN:-}" ]]; then
  echo "Set SEALHUB_TOKEN" >&2
  exit 1
fi

command -v hub >/dev/null || { echo "hub not on PATH; source ~/.config/sealhub/env" >&2; exit 1; }

apply_file() {
  local api_path="$1"
  local src="$2"
  local extra="${3:-}"
  if [[ ! -f "$src" ]]; then
    echo "skip missing $src" >&2
    return 0
  fi
  echo "apply $api_path <- $src" >&2
  # shellcheck disable=SC2086
  hub apply "$api_path" -f "$src" $extra
}

apply_file "live/ssh/id_ed25519" "${SSH_DIR}/id_ed25519" "-encrypt"
apply_file "live/ssh/id_ed25519.pub" "${SSH_DIR}/id_ed25519.pub" ""

if [[ -f "$TS_CONFIG" ]]; then
  apply_file "live/tailscale/config" "$TS_CONFIG" "-encrypt"
elif [[ -n "${TAILSCALE_AUTHKEY:-}" ]]; then
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  cat >"$tmp" <<EOF
{
  "version": "alpha0",
  "authKey": "${TAILSCALE_AUTHKEY}",
  "hostname": "${HOSTNAME_SHORT}",
  "acceptRoutes": true
}
EOF
  apply_file "live/tailscale/config" "$tmp" "-encrypt"
else
  echo "No $TS_CONFIG and TAILSCALE_AUTHKEY unset — skipping tailscale config" >&2
fi

echo "Done. Git paths: data/live/ssh/id_ed25519, data/live/ssh/id_ed25519.pub, data/live/tailscale/config"

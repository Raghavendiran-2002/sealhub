#!/usr/bin/env bash
# Copy /etc/sealhub secrets into pi-owned paths for rootless Podman bind mounts.
set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-/etc/sealhub}"
RUN_DIR="${RUN_DIR:-${HOME}/.local/share/sealhub/run}"

sudo_cmd() {
  if [[ -n "${SUDO_PASS:-}" ]]; then
    echo "$SUDO_PASS" | sudo -S "$@"
  elif sudo -n true 2>/dev/null; then
    sudo -n "$@"
  else
    return 1
  fi
}

read_host_file() {
  local path="$1"
  if [[ -r "$path" ]]; then
    cat "$path"
    return 0
  fi
  if sudo_cmd cat "$path" 2>/dev/null; then
    return 0
  fi
  echo "ERROR: cannot read $path as $USER — chown to pi on the host or set PI_SUDO_PASS on GitHub environment tailscale." >&2
  return 1
}

# Prefer pi-owned /etc/sealhub so future deploys work without sudo.
if [[ ! -r "$CONFIG_DIR/config.yaml" ]] && sudo_cmd true 2>/dev/null; then
  sudo_cmd chown "$USER:$USER" "$CONFIG_DIR/config.yaml" 2>/dev/null || true
  sudo_cmd chown "$USER:$USER" "$CONFIG_DIR/keyring" "$CONFIG_DIR/jwt-secret" 2>/dev/null || true
  sudo_cmd chmod 644 "$CONFIG_DIR/config.yaml" 2>/dev/null || true
  sudo_cmd chmod 600 "$CONFIG_DIR/keyring" "$CONFIG_DIR/jwt-secret" 2>/dev/null || true
fi

mkdir -p "$RUN_DIR"
for f in config.yaml keyring jwt-secret; do
  if [[ ! -f "$CONFIG_DIR/$f" ]]; then
    echo "missing $CONFIG_DIR/$f" >&2
    exit 1
  fi
done

_cfg_tmp="$(mktemp)"
read_host_file "$CONFIG_DIR/config.yaml" | sed \
  -e 's|keyringFile: /etc/sealhub/keyring|keyringFile: /run/secrets/keyring|g' \
  -e 's|jwtSecretFile: /etc/sealhub/jwt-secret|jwtSecretFile: /run/secrets/jwt-secret|g' \
  >"$_cfg_tmp"
if ! grep -q '^server:' "$_cfg_tmp"; then
  echo "ERROR: $CONFIG_DIR/config.yaml is not valid hubd YAML (got $(wc -c <"$_cfg_tmp") bytes). Replace placeholder content with a full config — see hack/pi/podman-setup.sh or docs/RESTORE-PI-MANUAL.md" >&2
  rm -f "$_cfg_tmp"
  exit 1
fi
mv "$_cfg_tmp" "$RUN_DIR/config.yaml"
read_host_file "$CONFIG_DIR/keyring" >"$RUN_DIR/keyring"
read_host_file "$CONFIG_DIR/jwt-secret" >"$RUN_DIR/jwt-secret"

chmod 644 "$RUN_DIR/config.yaml"
chmod 600 "$RUN_DIR/keyring" "$RUN_DIR/jwt-secret"

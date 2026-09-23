#!/usr/bin/env bash
# Copy /etc/sealhub secrets into pi-owned paths for rootless Podman bind mounts.
set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-/etc/sealhub}"
RUN_DIR="${RUN_DIR:-${HOME}/.local/share/sealhub/run}"

mkdir -p "$RUN_DIR"
for f in config.yaml keyring jwt-secret; do
  if [[ ! -f "$CONFIG_DIR/$f" ]]; then
    echo "missing $CONFIG_DIR/$f" >&2
    exit 1
  fi
  if [[ ! -r "$CONFIG_DIR/$f" ]]; then
    echo "ERROR: $CONFIG_DIR/$f not readable by $USER — run: sudo chown $USER:$USER $CONFIG_DIR/$f" >&2
    exit 1
  fi
  if [[ "$f" == config.yaml ]]; then
    sed -e 's|keyringFile: /etc/sealhub/keyring|keyringFile: /run/secrets/keyring|g' \
        -e 's|jwtSecretFile: /etc/sealhub/jwt-secret|jwtSecretFile: /run/secrets/jwt-secret|g' \
        "$CONFIG_DIR/config.yaml" >"$RUN_DIR/config.yaml"
  else
    cp -f "$CONFIG_DIR/$f" "$RUN_DIR/$f"
  fi
done
chmod 644 "$RUN_DIR/config.yaml"
chmod 600 "$RUN_DIR/keyring" "$RUN_DIR/jwt-secret"

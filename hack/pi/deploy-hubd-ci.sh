#!/usr/bin/env bash
# Remote deploy: pull hubd from GHCR and restart container (no image build on Pi).
# Preserves /etc/sealhub and /var/lib/sealhub/repo. Run as user pi.
set -euo pipefail

HUBD_IMAGE="${HUBD_IMAGE:?set HUBD_IMAGE e.g. ghcr.io/raghavendiran-2002/sealhub/hubd:0.1-latest}"
CONFIG_DIR="/etc/sealhub"
REPO_DIR="/var/lib/sealhub/repo"
RUN_DIR="${HOME}/.local/share/sealhub/run"

command -v podman >/dev/null || { echo "podman required"; exit 1; }

if [[ ! -f "$CONFIG_DIR/config.yaml" ]]; then
  echo "Missing $CONFIG_DIR/config.yaml — run hack/pi/podman-setup.sh once on the Pi first."
  exit 1
fi

sudo_cmd() {
  if [[ -n "${SUDO_PASS:-}" ]]; then
    echo "$SUDO_PASS" | sudo -S "$@"
  elif sudo -n true 2>/dev/null; then
    sudo -n "$@"
  else
    return 1
  fi
}

ensure_mount_permissions() {
  # Rootless Podman: container UID 0 == host user pi (not host root).
  if sudo_cmd true 2>/dev/null; then
    sudo_cmd chown "$USER:$USER" "$CONFIG_DIR/config.yaml" 2>/dev/null || true
    sudo_cmd chown "$USER:$USER" "$CONFIG_DIR/keyring" "$CONFIG_DIR/jwt-secret" 2>/dev/null || true
    sudo_cmd chmod 644 "$CONFIG_DIR/config.yaml" 2>/dev/null || true
    sudo_cmd chmod 600 "$CONFIG_DIR/keyring" "$CONFIG_DIR/jwt-secret" 2>/dev/null || true
    sudo_cmd chown -R "$USER:$USER" "$REPO_DIR" 2>/dev/null || true
  fi
  mkdir -p "$RUN_DIR"
  if [[ -r "$CONFIG_DIR/config.yaml" ]]; then
    cp -f "$CONFIG_DIR/config.yaml" "$RUN_DIR/config.yaml"
  elif sudo_cmd cat "$CONFIG_DIR/config.yaml" >"$RUN_DIR/config.yaml" 2>/dev/null; then
    :
  else
    echo "ERROR: cannot read $CONFIG_DIR/config.yaml — chown to pi or add PI_SUDO_PASS to tailscale env."
    exit 1
  fi
  chmod 644 "$RUN_DIR/config.yaml"
  for f in keyring jwt-secret; do
    if [[ -r "$CONFIG_DIR/$f" ]]; then
      cp -f "$CONFIG_DIR/$f" "$RUN_DIR/$f"
    else
      sudo_cmd cat "$CONFIG_DIR/$f" >"$RUN_DIR/$f"
    fi
    chmod 600 "$RUN_DIR/$f"
  done
}

if [[ -n "${GHCR_TOKEN:-}" ]]; then
  echo "$GHCR_TOKEN" | podman login ghcr.io -u "${GHCR_USER:-raghavendiran-2002}" --password-stdin
fi

ensure_mount_permissions

echo "Pulling $HUBD_IMAGE ..."
podman pull "$HUBD_IMAGE"

podman rm -f sealhub-hubd 2>/dev/null || true

podman run -d --name sealhub-hubd \
  --replace \
  --user 0:0 \
  -p 8080:8080 \
  -v "$RUN_DIR/config.yaml:/config/config.yaml:ro,z" \
  -v "$RUN_DIR/keyring:/run/secrets/keyring:ro,z" \
  -v "$RUN_DIR/jwt-secret:/run/secrets/jwt-secret:ro,z" \
  -v "$REPO_DIR:/var/lib/sealhub/repo:Z" \
  -v "$HOME/.ssh:/root/.ssh:ro,z" \
  -e HOME=/root \
  -e GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new" \
  "$HUBD_IMAGE"

for _ in $(seq 1 45); do
  if curl -sf http://127.0.0.1:8080/readyz >/dev/null 2>&1; then
    echo "SealHub hubd ready — image $HUBD_IMAGE"
    exit 0
  fi
  sleep 2
done

echo "hubd not ready:"
podman logs sealhub-hubd | tail -50
exit 1

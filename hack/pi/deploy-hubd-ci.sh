#!/usr/bin/env bash
# Remote deploy: pull hubd from GHCR and restart container (no image build on Pi).
# Preserves /etc/sealhub and /var/lib/sealhub/repo. Run as user pi.
set -euo pipefail

HUBD_IMAGE="${HUBD_IMAGE:?set HUBD_IMAGE e.g. ghcr.io/raghavendiran-2002/sealhub/hubd:0.1-latest}"
CONFIG_DIR="/etc/sealhub"
REPO_DIR="/var/lib/sealhub/repo"

command -v podman >/dev/null || { echo "podman required"; exit 1; }

if [[ ! -f "$CONFIG_DIR/config.yaml" ]]; then
  echo "Missing $CONFIG_DIR/config.yaml — run hack/pi/podman-setup.sh once on the Pi first."
  exit 1
fi

ensure_mount_permissions() {
  # Rootless Podman maps container UID 0 → host pi; secrets must be readable by pi.
  if [[ -r "$CONFIG_DIR/config.yaml" ]]; then
    sudo chown "$USER:$USER" "$CONFIG_DIR/config.yaml" 2>/dev/null || true
    sudo chmod 644 "$CONFIG_DIR/config.yaml" 2>/dev/null || true
  fi
  for f in keyring jwt-secret; do
    if [[ -f "$CONFIG_DIR/$f" ]]; then
      sudo chown "$USER:$USER" "$CONFIG_DIR/$f" 2>/dev/null || true
      sudo chmod 600 "$CONFIG_DIR/$f" 2>/dev/null || true
    fi
  done
  sudo chown -R "$USER:$USER" "$REPO_DIR" 2>/dev/null || true
}

if [[ -n "${GHCR_TOKEN:-}" ]]; then
  echo "$GHCR_TOKEN" | podman login ghcr.io -u "${GHCR_USER:-raghavendiran-2002}" --password-stdin
fi

ensure_mount_permissions

echo "Pulling $HUBD_IMAGE ..."
podman pull "$HUBD_IMAGE"

podman rm -f sealhub-hubd 2>/dev/null || true

# UID 0 in container → pi on host (rootless); reads pi-owned keyring/config mounts.
podman run -d --name sealhub-hubd \
  --replace \
  --user 0:0 \
  -p 8080:8080 \
  -v "$CONFIG_DIR/config.yaml:/config/config.yaml:ro,z" \
  -v "$CONFIG_DIR/keyring:/run/secrets/keyring:ro,z" \
  -v "$CONFIG_DIR/jwt-secret:/run/secrets/jwt-secret:ro,z" \
  -v "$REPO_DIR:/var/lib/sealhub/repo:Z" \
  -v "$HOME/.ssh:/root/.ssh:ro,z" \
  -e HOME=/root \
  -e GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new" \
  "$HUBD_IMAGE"

for _ in $(seq 1 30); do
  if curl -sf http://127.0.0.1:8080/readyz >/dev/null 2>&1; then
    echo "SealHub hubd ready — image $HUBD_IMAGE"
    exit 0
  fi
  sleep 2
done

echo "hubd not ready:"
podman logs sealhub-hubd | tail -50
exit 1

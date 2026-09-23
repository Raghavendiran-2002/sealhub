#!/usr/bin/env bash
# Remote deploy: pull new hubd GHCR image, rebuild git+ssh wrapper, restart container.
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

if [[ -n "${GHCR_TOKEN:-}" ]]; then
  echo "$GHCR_TOKEN" | podman login ghcr.io -u "${GHCR_USER:-raghavendiran-2002}" --password-stdin
fi

echo "Pulling $HUBD_IMAGE ..."
podman pull "$HUBD_IMAGE"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
cat >"$tmpdir/Containerfile" <<EOF
FROM ${HUBD_IMAGE} AS hubd
FROM docker.io/library/debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends git openssh-client ca-certificates curl \\
  && rm -rf /var/lib/apt/lists/*
COPY --from=hubd /hubd /hubd
EXPOSE 8080
ENTRYPOINT ["/hubd"]
CMD ["/config/config.yaml"]
EOF
podman build -t sealhub-hubd:pi "$tmpdir"

podman rm -f sealhub-hubd 2>/dev/null || true

podman run -d --name sealhub-hubd \
  --replace \
  -p 8080:8080 \
  -v "$CONFIG_DIR/config.yaml:/config/config.yaml:ro" \
  -v "$CONFIG_DIR/keyring:/run/secrets/keyring:ro" \
  -v "$CONFIG_DIR/jwt-secret:/run/secrets/jwt-secret:ro" \
  -v "$REPO_DIR:/var/lib/sealhub/repo" \
  -v "$HOME/.ssh:/root/.ssh:ro" \
  -e HOME=/root \
  -e GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new" \
  sealhub-hubd:pi

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

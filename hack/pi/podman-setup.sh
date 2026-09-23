#!/usr/bin/env bash
# Run ON the Raspberry Pi (Podman already installed).
# Pulls ghcr.io/.../hubd:0.1.4, wraps with git+ssh, clones sealhub-data, starts hubd.
set -euo pipefail

HUBD_IMAGE="${HUBD_IMAGE:-ghcr.io/raghavendiran-2002/sealhub/hubd:0.1.4}"
PI_IP="${PI_IP:-192.168.1.12}"
CONFIG_DIR="/etc/sealhub"
REPO_DIR="/var/lib/sealhub/repo"
BOOTSTRAP_TOKEN="${BOOTSTRAP_TOKEN:-pi-homelab-bootstrap-change-me}"
DATA_REPO="${DATA_REPO:-git@github.com:Raghavendiran-2002/sealhub-data.git}"

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Run as user pi, not root (use: SUDO_PASS=... bash $0)"
  exit 1
fi

sudo_cmd() {
  if [[ -n "${SUDO_PASS:-}" ]]; then
    echo "$SUDO_PASS" | sudo -S "$@"
  else
    sudo "$@"
  fi
}

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
ssh-keyscan -t ed25519,rsa github.com >>"$HOME/.ssh/known_hosts" 2>/dev/null || true

command -v podman >/dev/null || { echo "podman required"; exit 1; }

for dep in git curl openssh-client; do
  if ! command -v "${dep%%-*}" >/dev/null 2>&1 && ! command -v "$dep" >/dev/null 2>&1; then
    sudo_cmd apt-get update -qq
    sudo_cmd apt-get install -y git curl openssh-client ca-certificates
    break
  fi
done

sudo_cmd mkdir -p "$CONFIG_DIR" "$REPO_DIR"
sudo_cmd chown -R "$USER:$USER" "$REPO_DIR" 2>/dev/null || true

if [[ ! -f "$CONFIG_DIR/keyring" ]]; then
  head -c 32 /dev/urandom | base64 | sudo_cmd tee "$CONFIG_DIR/keyring" >/dev/null
  sudo_cmd chmod 600 "$CONFIG_DIR/keyring"
  sudo_cmd chown "$USER:$USER" "$CONFIG_DIR/keyring"
fi

if [[ ! -f "$CONFIG_DIR/jwt-secret" ]]; then
  head -c 32 /dev/urandom | base64 | sudo_cmd tee "$CONFIG_DIR/jwt-secret" >/dev/null
  sudo_cmd chmod 600 "$CONFIG_DIR/jwt-secret"
  sudo_cmd chown "$USER:$USER" "$CONFIG_DIR/jwt-secret"
fi

sudo_cmd tee "$CONFIG_DIR/config.yaml" >/dev/null <<EOF
server:
  listen: ":8080"
  externalURL: "http://${PI_IP}:8080"

github:
  owner: Raghavendiran-2002
  repo: sealhub-data
  branch: main
  auth:
    type: ssh

git:
  localPath: /var/lib/sealhub/repo

encryption:
  keyringFile: /run/secrets/keyring

auth:
  bootstrapToken: "${BOOTSTRAP_TOKEN}"
  jwtSecretFile: /run/secrets/jwt-secret

freshness:
  pollInterval: "30s"
EOF
sudo_cmd chmod 644 "$CONFIG_DIR/config.yaml"

if [[ -d "$REPO_DIR/.git" ]]; then
  : ok
elif [[ -d "$REPO_DIR" ]] && [[ -n "$(ls -A "$REPO_DIR" 2>/dev/null)" ]]; then
  rm -rf "$REPO_DIR"/*
fi

if [[ ! -d "$REPO_DIR/.git" ]]; then
  echo "Cloning $DATA_REPO ..."
  git clone --branch main --single-branch "$DATA_REPO" "$REPO_DIR"
fi

echo "Pulling $HUBD_IMAGE ..."
podman pull "$HUBD_IMAGE"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
cat >"$tmpdir/Containerfile" <<EOF
FROM ${HUBD_IMAGE} AS hubd
FROM docker.io/library/debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends git openssh-client ca-certificates \\
  && rm -rf /var/lib/apt/lists/*
COPY --from=hubd /hubd /hubd
EXPOSE 8080
ENTRYPOINT ["/hubd"]
CMD ["/config/config.yaml"]
EOF
podman build -t sealhub-hubd:pi "$tmpdir"

podman rm -f sealhub-hubd 2>/dev/null || true

# Rootless Podman: do NOT use --user uid:gid — that maps to a subuid on the host
# which cannot read pi-owned files (keyring) even after chown pi:pi.
# UID 0 inside the container maps to the host pi user and can read mounts + git ssh.
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

echo "Waiting for hubd..."
ready=0
for _ in $(seq 1 45); do
  if curl -sf http://127.0.0.1:8080/readyz >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 2
done
if [[ "$ready" -ne 1 ]]; then
  echo "hubd not ready — logs:"
  podman logs sealhub-hubd | tail -40
  exit 1
fi

echo "--- sample config (data/config/homelab/settings.yaml) ---"
curl -sf -H "Authorization: Bearer ${BOOTSTRAP_TOKEN}" \
  "http://127.0.0.1:8080/api/v1/documents/config/homelab/settings.yaml"
echo
echo "--- sample secret (data/secrets/homelab/sample.yaml) ---"
curl -sf -H "Authorization: Bearer ${BOOTSTRAP_TOKEN}" \
  "http://127.0.0.1:8080/api/v1/documents/secrets/homelab/sample.yaml"
echo
echo "OK — SealHub: http://${PI_IP}:8080"
echo "Bootstrap token: ${BOOTSTRAP_TOKEN}"

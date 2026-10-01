#!/usr/bin/env bash
# Full Pi bootstrap: install Podman hubd + hub CLI, clone sealhub-data, restore live/ assets.
# Run ON the Pi as user pi:
#   SUDO_PASS=... PI_IP=192.168.1.14 bash bootstrap-pi-from-sealhub-data.sh
#
# Optional: copy /etc/sealhub/keyring + jwt-secret from the previous Pi first so hub can
# decrypt documents from sealhub-data (same encryption keyring).
set -euo pipefail

PI_IP="${PI_IP:-192.168.1.14}"
SUDO_PASS="${SUDO_PASS:-}"
SEALHUB_REPO="${SEALHUB_REPO:-https://github.com/Raghavendiran-2002/sealhub.git}"
SEALHUB_DIR="${SEALHUB_DIR:-$HOME/sealhub}"

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Run as pi, not root" >&2
  exit 1
fi

sudo_cmd() {
  if [[ -n "$SUDO_PASS" ]]; then
    echo "$SUDO_PASS" | sudo -S "$@"
  else
    sudo "$@"
  fi
}

if ! command -v podman >/dev/null; then
  sudo_cmd apt-get update -qq
  sudo_cmd apt-get install -y podman git curl openssh-client ca-certificates jq
fi

if [[ ! -d "$SEALHUB_DIR/.git" ]]; then
  git clone --depth 1 "$SEALHUB_REPO" "$SEALHUB_DIR"
fi

cd "$SEALHUB_DIR"
git pull --ff-only || true

export HUBD_IMAGE="${HUBD_IMAGE:-ghcr.io/raghavendiran-2002/sealhub/hubd:0.1-latest}"
export PI_IP BOOTSTRAP_TOKEN="${BOOTSTRAP_TOKEN:-pi-homelab-bootstrap-change-me}" SUDO_PASS
bash hack/pi/podman-setup.sh

chmod +x hack/shared/install-hub-cli.sh hack/pi/install-hub-cli.sh hack/pi/restore-from-sealhub.sh
GOARM="" 
case "$(uname -m)" in armv7l) export GOARM=7 ;; esac
go build -o /tmp/sealhub-hub ./cmd/hub 2>/dev/null || hack/pi/install-hub-cli.sh /tmp/sealhub-hub 2>/dev/null || true
if [[ ! -x "$HOME/.local/bin/hub" ]]; then
  go build -o /tmp/sealhub-hub ./cmd/hub && hack/shared/install-hub-cli.sh /tmp/sealhub-hub hack/pi/sealhub.env.example
fi

# shellcheck disable=SC1091
source "$HOME/.config/sealhub/env" 2>/dev/null || export SEALHUB_SERVER="http://127.0.0.1:8080" SEALHUB_TOKEN="$BOOTSTRAP_TOKEN"

if ! curl -sf "${SEALHUB_SERVER}/readyz" >/dev/null; then
  echo "hubd not ready" >&2
  exit 1
fi

bash hack/pi/restore-from-sealhub.sh

echo "SealHub: http://${PI_IP}:8080"

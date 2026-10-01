#!/usr/bin/env bash
# On Pi with hubd running locally: restore live/ assets from SealHub API into ~/.ssh and tailscale.
set -euo pipefail

export SEALHUB_SERVER="${SEALHUB_SERVER:-http://127.0.0.1:8080}"
export SEALHUB_TOKEN="${SEALHUB_TOKEN:-pi-homelab-bootstrap-change-me}"

command -v hub >/dev/null || { echo "hub not on PATH" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq required" >&2; exit 1; }

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

fetch_doc() {
  hub get "$1" -o json | jq -r '.Document'
}

echo "Restoring SSH keys..."
if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
  echo "  ~/.ssh/id_ed25519 already present"
else
  fetch_doc live/ssh/id_ed25519 >"$HOME/.ssh/id_ed25519"
  chmod 600 "$HOME/.ssh/id_ed25519"
fi
if [[ -f "$HOME/.ssh/id_ed25519.pub" ]]; then
  echo "  ~/.ssh/id_ed25519.pub already present"
else
  fetch_doc live/ssh/id_ed25519.pub >"$HOME/.ssh/id_ed25519.pub"
  chmod 644 "$HOME/.ssh/id_ed25519.pub"
fi

if hub get live/ssh/config -o json >/dev/null 2>&1; then
  fetch_doc live/ssh/config >"$HOME/.ssh/config"
  chmod 600 "$HOME/.ssh/config"
fi

if hub get live/tailscale/config -o json >/dev/null 2>&1; then
  echo "Restoring tailscale config (sudo)..."
  fetch_doc live/tailscale/config | sudo tee /etc/tailscale/config.json >/dev/null
  sudo chmod 600 /etc/tailscale/config.json
elif [[ -f "$HOME/.sealhub-backup/tailscale-config.json" ]]; then
  echo "Restoring tailscale config from ~/.sealhub-backup (sudo)..."
  sudo mkdir -p /etc/tailscale
  sudo cp "$HOME/.sealhub-backup/tailscale-config.json" /etc/tailscale/config.json
  sudo chmod 600 /etc/tailscale/config.json
fi

if hub get secrets/homelab/pocket-id.env -o json >/dev/null 2>&1; then
  mkdir -p "$HOME/pocket-id"
  fetch_doc secrets/homelab/pocket-id.env >"$HOME/pocket-id/.env"
  chmod 600 "$HOME/pocket-id/.env"
  echo "Pocket ID .env restored to ~/pocket-id/.env"
fi

if hub get pocket/homelab/pocket-id.db.yaml -o json >/dev/null 2>&1; then
  command -v hub >/dev/null
  POCKET_ID_HOME="${POCKET_ID_HOME:-$HOME/pocket-id}" hub pocket restore -dir "$POCKET_ID_HOME" -no-stop 2>/dev/null || true
fi

echo "Restore complete."

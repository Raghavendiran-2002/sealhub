#!/usr/bin/env bash
# From your Mac: install SealHub on Pi and restore live/ SSH + tailscale from sealhub-data.
# Usage: PI_HOST=192.168.1.14 PI_PASS=... ./hack/local/bootstrap-pi-192.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PI_HOST="${PI_HOST:-192.168.1.14}"
PI_USER="${PI_USER:-pi}"
PI_PASS="${PI_PASS:?set PI_PASS}"
PI_IP="${PI_IP:-$PI_HOST}"

command -v sshpass >/dev/null || { echo "sshpass required" >&2; exit 1; }
command -v gh >/dev/null || { echo "gh required" >&2; exit 1; }

SSH=(sshpass -p "$PI_PASS" ssh -o StrictHostKeyChecking=accept-new
  -o PreferredAuthentications=password -o PubkeyAuthentication=no
  "${PI_USER}@${PI_HOST}")
SCP=(sshpass -p "$PI_PASS" scp -o StrictHostKeyChecking=accept-new
  -o PreferredAuthentications=password -o PubkeyAuthentication=no)

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# SSH public key (plaintext in git)
gh api repos/Raghavendiran-2002/sealhub-data/contents/data/live/ssh/id_ed25519.pub -q .content \
  | tr -d '\n' | base64 -d | python3 "$ROOT/hack/pi/extract-envelope-document.py" >"$TMP/id_ed25519.pub"

# If hub on old Pi is down, restore private key via local hub cache or prior export at $HOME/.sealhub-backup/id_ed25519
if [[ -f "${SEALHUB_BACKUP_KEY:-$HOME/.sealhub-backup/id_ed25519}" ]]; then
  cp "${SEALHUB_BACKUP_KEY:-$HOME/.sealhub-backup/id_ed25519}" "$TMP/id_ed25519"
  chmod 600 "$TMP/id_ed25519"
else
  echo "Trying hub get against SEALHUB_SERVER (optional)..." >&2
  if [[ -n "${SEALHUB_SERVER:-}" && -n "${SEALHUB_TOKEN:-}" ]] && command -v hub >/dev/null; then
    hub get live/ssh/id_ed25519 -o json | python3 -c "import json,sys; print(json.load(sys.stdin)['Document'])" >"$TMP/id_ed25519"
    chmod 600 "$TMP/id_ed25519"
  else
    echo "Missing private key: set SEALHUB_SERVER+SEALHUB_TOKEN+hub, or place key at ~/.sealhub-backup/id_ed25519" >&2
    exit 1
  fi
fi

"${SCP[@]}" "$TMP/id_ed25519" "$TMP/id_ed25519.pub" "${PI_USER}@${PI_HOST}:~/.ssh/"
if [[ -f "$HOME/.sealhub-backup/tailscale-config.json" ]]; then
  "${SSH[@]}" 'mkdir -p ~/.sealhub-backup'
  "${SCP[@]}" "$HOME/.sealhub-backup/tailscale-config.json" "${PI_USER}@${PI_HOST}:~/.sealhub-backup/"
fi
"${SSH[@]}" 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_ed25519 && chmod 644 ~/.ssh/id_ed25519.pub'

# Optional: restore keyring from backup so hubd can decrypt sealhub-data blobs
if [[ -f "${SEALHUB_BACKUP_KEYRING:-$HOME/.sealhub-backup/keyring}" ]]; then
  "${SCP[@]}" "${SEALHUB_BACKUP_KEYRING:-$HOME/.sealhub-backup/keyring}" "${PI_USER}@${PI_HOST}:/tmp/sealhub-keyring"
  "${SCP[@]}" "${SEALHUB_BACKUP_JWT:-$HOME/.sealhub-backup/jwt-secret}" "${PI_USER}@${PI_HOST}:/tmp/sealhub-jwt-secret" 2>/dev/null || true
fi

# Sync sealhub repo
tar -C "$ROOT" -czf "$TMP/sealhub.tgz" --exclude=.git .
"${SCP[@]}" "$TMP/sealhub.tgz" "${PI_USER}@${PI_HOST}:/tmp/sealhub.tgz"
GH_TOKEN=$(gh auth token)

"${SSH[@]}" "set -euo pipefail
  PI_IP='$PI_IP' SUDO_PASS='$PI_PASS' GH_TOKEN='$GH_TOKEN'
  mkdir -p ~/sealhub && tar -xzf /tmp/sealhub.tgz -C ~/sealhub
  if [[ -f /tmp/sealhub-keyring ]]; then
    echo \"\$SUDO_PASS\" | sudo -S mkdir -p /etc/sealhub
    echo \"\$SUDO_PASS\" | sudo -S cp /tmp/sealhub-keyring /etc/sealhub/keyring
    echo \"\$SUDO_PASS\" | sudo -S cp /tmp/sealhub-jwt-secret /etc/sealhub/jwt-secret 2>/dev/null || true
    echo \"\$SUDO_PASS\" | sudo -S chown pi:pi /etc/sealhub/keyring /etc/sealhub/jwt-secret 2>/dev/null || true
    echo \"\$SUDO_PASS\" | sudo -S chown pi:pi /etc/sealhub/keyring
  fi
  export DATA_REPO=\"https://x-access-token:\${GH_TOKEN}@github.com/Raghavendiran-2002/sealhub-data.git\"
  command -v go >/dev/null || { echo \"\$SUDO_PASS\" | sudo -S apt-get update -qq; echo \"\$SUDO_PASS\" | sudo -S apt-get install -y golang-go; }
  bash ~/sealhub/hack/pi/podman-setup.sh
  chmod +x ~/sealhub/hack/shared/install-hub-cli.sh
  (cd ~/sealhub && go build -o /tmp/hub ./cmd/hub && ~/sealhub/hack/shared/install-hub-cli.sh /tmp/hub ~/sealhub/hack/pi/sealhub.env.example)
  source ~/.config/sealhub/env
  bash ~/sealhub/hack/pi/restore-from-sealhub.sh
"

echo "Done. hubd: http://${PI_IP}:8080"

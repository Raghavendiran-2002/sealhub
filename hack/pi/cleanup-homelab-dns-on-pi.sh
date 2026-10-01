#!/usr/bin/env bash
# Run ON live: remove homelab-dnsmasq container and optional native dnsmasq config.
set -euo pipefail

SUDO_PASS="${SUDO_PASS:-}"
sudo_cmd() {
  if [[ -n "$SUDO_PASS" ]]; then echo "$SUDO_PASS" | sudo -S "$@"; else sudo "$@"; fi
}

podman rm -f homelab-dnsmasq 2>/dev/null || true
rm -rf "$HOME/podman-compose/dnsmasq" 2>/dev/null || true

if systemctl is-active dnsmasq >/dev/null 2>&1; then
  sudo_cmd systemctl stop dnsmasq
  sudo_cmd systemctl disable dnsmasq 2>/dev/null || true
fi
if [[ -f /etc/dnsmasq.d/homelab-id.conf ]]; then
  sudo_cmd rm -f /etc/dnsmasq.d/homelab-id.conf
  sudo_cmd systemctl restart dnsmasq 2>/dev/null || true
fi

echo "DNS cleanup done. Expected podman: sealhub-hubd, pocket-id, pocket-id-cloudflared"

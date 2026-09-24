#!/usr/bin/env bash
# Run on Raspberry Pi (arm64) as user pi.
set -euo pipefail

SEALHUB_REPO="${SEALHUB_REPO:-git@github.com:Raghavendiran-2002/sealhub.git}"
DATA_REPO="${DATA_REPO:-git@github.com:Raghavendiran-2002/sealhub-data.git}"
INSTALL_DIR="${INSTALL_DIR:-/opt/sealhub}"
CONFIG_DIR="${CONFIG_DIR:-/etc/sealhub}"
BOOTSTRAP_TOKEN="${BOOTSTRAP_TOKEN:-pi-homelab-bootstrap-change-me}"

sudo mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" /var/lib/sealhub/repo
sudo chown -R "$USER:$USER" "$INSTALL_DIR" /var/lib/sealhub

if ! command -v go >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y git golang-go
fi

if [[ ! -d "$INSTALL_DIR/sealhub/.git" ]]; then
  git clone --depth 1 "$SEALHUB_REPO" "$INSTALL_DIR/sealhub"
fi

cd "$INSTALL_DIR/sealhub"
git pull --ff-only || true
go build -o "$INSTALL_DIR/hubd" ./cmd/hubd
chmod +x hack/shared/install-hub-cli.sh
go build -o /tmp/sealhub-hub ./cmd/hub
hack/shared/install-hub-cli.sh /tmp/sealhub-hub hack/pi/sealhub.env.example

if [[ ! -f "$CONFIG_DIR/keyring" ]]; then
  head -c 32 /dev/urandom | base64 | sudo tee "$CONFIG_DIR/keyring" >/dev/null
  sudo chmod 600 "$CONFIG_DIR/keyring"
fi

if [[ ! -f "$CONFIG_DIR/jwt-secret" ]]; then
  head -c 32 /dev/urandom | base64 | sudo tee "$CONFIG_DIR/jwt-secret" >/dev/null
  sudo chmod 600 "$CONFIG_DIR/jwt-secret"
fi

sudo tee "$CONFIG_DIR/config.yaml" >/dev/null <<EOF
server:
  listen: ":8080"
  externalURL: "http://192.168.1.12:8080"

github:
  owner: Raghavendiran-2002
  repo: sealhub-data
  branch: main
  auth:
    type: ssh

git:
  localPath: /var/lib/sealhub/repo

encryption:
  keyringFile: $CONFIG_DIR/keyring

auth:
  bootstrapToken: "$BOOTSTRAP_TOKEN"
  jwtSecretFile: $CONFIG_DIR/jwt-secret

freshness:
  pollInterval: "30s"
EOF
sudo chmod 600 "$CONFIG_DIR/config.yaml"

sudo tee /etc/systemd/system/sealhub-hubd.service >/dev/null <<EOF
[Unit]
Description=SealHub hubd
After=network-online.target

[Service]
Type=simple
User=$USER
Environment=SEALHUB_CONFIG=$CONFIG_DIR/config.yaml
ExecStart=$INSTALL_DIR/hubd $CONFIG_DIR/config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable sealhub-hubd
sudo systemctl restart sealhub-hubd

echo "SealHub hubd started. Test:"
echo "  source ~/.config/sealhub/env && hub list config/homelab"
echo "  hub get config/homelab/settings.yaml"
echo "  hub get secrets/homelab/sample.yaml"

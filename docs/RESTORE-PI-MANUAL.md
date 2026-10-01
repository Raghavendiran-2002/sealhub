# Manual Pi setup + restore from sealhub-data (CLI)

Use this when bringing up a **new** Pi (e.g. `192.168.1.14`, hostname `live`) and restoring **`data/live/...`** and homelab docs from **sealhub-data** via **hub** / **hubd**.

## Prerequisites

1. **Valid `/etc/sealhub/config.yaml`** — must be real YAML (starts with `server:`). A one-line placeholder like `…` or a sudo password will make hubd fail with `cannot unmarshal !!str`.

2. **Same encryption keyring as before** — copy from the old Pi (required to decrypt `live/ssh/id_ed25519`, `live/tailscale/config`, etc. in git):
   ```bash
   # on OLD Pi (if still available)
   sudo cat /etc/sealhub/keyring
   sudo cat /etc/sealhub/jwt-secret
   ```
   On the **new** Pi, create `/etc/sealhub/keyring` and `/etc/sealhub/jwt-secret` with the **same contents**, owned by `pi`, mode `600` (keyring/jwt) / `644` (config.yaml).

2. **GitHub access** to `Raghavendiran-2002/sealhub-data` — deploy key in `~/.ssh/id_ed25519` **or** HTTPS clone (see below).

3. **Bootstrap token** — same as before, default in docs: `pi-homelab-bootstrap-change-me` (must match `auth.bootstrapToken` in `/etc/sealhub/config.yaml`).

---

## Step 1 — SSH to the new Pi

```bash
ssh pi@192.168.1.14
```

---

## Step 2 — Install hubd (Podman)

```bash
sudo apt-get update
sudo apt-get install -y podman git curl openssh-client golang-go jq

git clone --depth 1 https://github.com/Raghavendiran-2002/sealhub.git ~/sealhub
cd ~/sealhub

export PI_IP=192.168.1.14
export SUDO_PASS='your-sudo-password'
export BOOTSTRAP_TOKEN='pi-homelab-bootstrap-change-me'

# If keyring/jwt-secret already copied to /etc/sealhub/, podman-setup will NOT regenerate them.
bash hack/pi/podman-setup.sh
```

If **Git clone of sealhub-data fails** (no SSH key yet), clone once with a GitHub PAT:

```bash
export DATA_REPO="https://x-access-token:YOUR_GITHUB_PAT@github.com/Raghavendiran-2002/sealhub-data.git"
bash hack/pi/podman-setup.sh
```

Check hubd:

```bash
curl -sf http://127.0.0.1:8080/healthz && echo ok
curl -sf http://127.0.0.1:8080/readyz && echo ready
```

---

## Step 3 — Install `hub` CLI on the Pi

```bash
cd ~/sealhub
./hack/pi/install-hub-cli.sh
source ~/.config/sealhub/env
export SEALHUB_SERVER=http://127.0.0.1:8080
export SEALHUB_TOKEN='pi-homelab-bootstrap-change-me'

hub list live/
```

You should see paths like `live/ssh/id_ed25519`, `live/ssh/id_ed25519.pub`, `live/tailscale/config`.

---

## Step 4 — Restore `live/` assets (manual `hub get`)

API paths map to git files under **`data/live/...`** in sealhub-data.

### SSH keys

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh

hub get live/ssh/id_ed25519 -o json | jq -r '.Document' > ~/.ssh/id_ed25519
hub get live/ssh/id_ed25519.pub -o json | jq -r '.Document' > ~/.ssh/id_ed25519.pub
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
```

Optional GitHub `~/.ssh/config` if stored:

```bash
hub get live/ssh/config -o json | jq -r '.Document' > ~/.ssh/config
chmod 600 ~/.ssh/config
```

Test GitHub:

```bash
ssh -T git@github.com
```

### Tailscale daemon config

```bash
sudo mkdir -p /etc/tailscale
hub get live/tailscale/config -o json | jq -r '.Document' | sudo tee /etc/tailscale/config.json >/dev/null
sudo chmod 600 /etc/tailscale/config.json
```

Start tailscaled with config (distro-dependent), e.g.:

```bash
sudo tailscaled --config=/etc/tailscale/config.json
# or enable your systemd unit if packaged
```

### Pocket ID (if backed up earlier)

**From `live/pocket-id/` (Mac: `hack/local/store-pocket-live.sh`):**

```bash
mkdir -p ~/pocket-id/data
hub get live/pocket-id/encryption.key -o json | jq -r '.Document' | tr -d '\n' > /tmp/enc
hub get live/cloudflare/token.txt -o json | jq -r '.Document' | tr -d '\n' > /tmp/tunnel
cat > ~/pocket-id/.env <<EOF
ENCRYPTION_KEY=$(cat /tmp/enc)
TUNNEL_TOKEN=$(cat /tmp/tunnel)
APP_URL=https://id.raghavendiran.cloud
TRUST_PROXY=true
EOF
chmod 600 ~/pocket-id/.env
rm -f /tmp/enc /tmp/tunnel
hub get live/pocket-id/db -o json | python3 -c "import json,sys; open(sys.argv[1],'wb').write(json.load(sys.stdin)['Document'].encode('latin-1'))" ~/pocket-id/data/pocket-id.db
chmod 600 ~/pocket-id/data/pocket-id.db
bash ~/sealhub/hack/pi/run-pocket-id-podman.sh
```

**Legacy homelab paths (`pocket/` + `secrets/`):**

```bash
mkdir -p ~/pocket-id
hub get secrets/homelab/pocket-id.env -o json | jq -r '.Document' > ~/pocket-id/.env
chmod 600 ~/pocket-id/.env

export POCKET_ID_HOME=~/pocket-id
hub pocket restore -dir ~/pocket-id -no-stop
```

### Other homelab docs

```bash
hub list config/homelab
hub get config/homelab/settings.yaml
hub list secrets/homelab
```

---

## Step 5 — From your Mac (optional)

Point at the new Pi once hubd listens on LAN/Tailscale:

```bash
source ~/path/to/sealhub/hack/local/sealhub.env   # or ~/.config/sealhub/env
export SEALHUB_SERVER=http://192.168.1.14:8080
export SEALHUB_TOKEN='pi-homelab-bootstrap-change-me'

hub list live/
hub get live/ssh/id_ed25519.pub
```

---

## Troubleshooting

| Problem | Fix |
|--------|-----|
| `hub get live/ssh/id_ed25519` gibberish or error | Wrong **keyring** — must match the Pi that originally encrypted data |
| `git clone` sealhub-data fails | Restore **SSH key** first (step 4), or use **HTTPS `DATA_REPO`** with PAT |
| `hub: command not found` | `source ~/.config/sealhub/env` or `./hack/pi/install-hub-cli.sh` |
| Empty `hub list live/` | hubd repo not cloned — check `podman logs sealhub-hubd`, `/var/lib/sealhub/repo` |

Helper script (same steps as above): `hack/pi/restore-from-sealhub.sh`

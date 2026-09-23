# SealHub on Raspberry Pi (hubd + CLI)

Runbook for **hubd** on a Pi (e.g. **`live`**) with **Podman**, **GHCR** images, and the **`hub`** CLI. Data lives in GitHub repo **[sealhub-data](https://github.com/Raghavendiran-2002/sealhub-data)**.

For GitHub Actions deploy over Tailscale, see **[DEPLOY-CI.md](DEPLOY-CI.md)** and **[TAILSCALE-OIDC-CI.md](TAILSCALE-OIDC-CI.md)**.

---

## Architecture

```text
  hub CLI  ──HTTP──►  hubd (Podman)  ──git push──►  sealhub-data (GitHub)
                           │
                           ├── /var/lib/sealhub/repo  (clone, mounted)
                           ├── ~/.ssh → container (git@github.com)
                           └── ~/.local/share/sealhub/run/  (pi-owned config copies)
```

- **Image:** `ghcr.io/raghavendiran-2002/sealhub/hubd:0.1-latest` (built in CI; includes `git` + `openssh`).
- **No image build on the Pi** — only `podman pull` + `run`.
- **SSH auth** to GitHub for the data repo (`github.auth.type: ssh`).

---

## Prerequisites

| Requirement | Notes |
|-------------|--------|
| Raspberry Pi OS, user **`pi`** | Rootless Podman |
| **Podman** | `podman --version` |
| **GitHub SSH** | `ssh -T git@github.com` works as `pi` |
| **sealhub-data** access | Deploy key or collaborator on private repo |
| **GHCR** | Public pull, or `podman login ghcr.io` with `read:packages` PAT |
| **Tailscale** (optional) | Hostname e.g. `live`, tag `tag:homelab`, `tailscale set --ssh` for CI |

---

## One-time bootstrap

On the Pi:

```bash
git clone --depth 1 git@github.com:Raghavendiran-2002/sealhub.git ~/sealhub
cd ~/sealhub
chmod +x hack/pi/podman-setup.sh
export SUDO_PASS='your-sudo-password'   # creates /etc/sealhub
export BOOTSTRAP_TOKEN='choose-a-strong-token'   # optional; default in script
export PI_IP='100.72.63.104'   # or 192.168.x.x — used in externalURL
./hack/pi/podman-setup.sh
```

Script actions:

1. Creates **`/etc/sealhub/`** — `config.yaml`, `keyring`, `jwt-secret` (owned by **`pi`**).
2. Clones **`/var/lib/sealhub/repo`** → `sealhub-data`.
3. Sets **local git identity** on the data repo (`SealHub Pi` / `sealhub@live`).
4. Pulls **`hubd:0.1-latest`**, copies config into **`~/.local/share/sealhub/run/`**, starts **`sealhub-hubd`**.

Default bootstrap token (if unset): `pi-homelab-bootstrap-change-me` — change in production.

---

## Paths and permissions (important)

| Path | Purpose |
|------|---------|
| `/etc/sealhub/config.yaml` | Hub config (host); must be readable by **`pi`** |
| `/etc/sealhub/keyring` | AES keyring (host); mode `600`, owner **`pi`** |
| `/etc/sealhub/jwt-secret` | JWT signing secret |
| `~/.local/share/sealhub/run/` | **Pi-owned copies** mounted into the container |
| `/var/lib/sealhub/repo` | Git clone of sealhub-data |

### Config inside the container

Host paths in **`config.yaml`** must use **container** locations:

```yaml
encryption:
  keyringFile: /run/secrets/keyring
auth:
  jwtSecretFile: /run/secrets/jwt-secret
```

**Not** `/etc/sealhub/...` — hubd runs in Podman and only sees mount targets.

`hack/pi/sync-run-config.sh` rewrites those paths when copying into `run/`.

### Rootless Podman rule

Container **`--user 0:0`** maps to host user **`pi`**, not host root. Files must be **`pi:pi`** (or world-readable for config). If **`config.yaml`** is **`root:root` mode 600`**, hubd fails with **`permission denied`**.

Fix on the Pi:

```bash
sudo chown pi:pi /etc/sealhub/config.yaml /etc/sealhub/keyring /etc/sealhub/jwt-secret
sudo chmod 644 /etc/sealhub/config.yaml
sudo chmod 600 /etc/sealhub/keyring /etc/sealhub/jwt-secret
```

---

## Manual deploy / upgrade (same as CI)

```bash
cd ~/sealhub
git pull
export HUBD_IMAGE=ghcr.io/raghavendiran-2002/sealhub/hubd:0.1-latest
./hack/pi/deploy-hubd-ci.sh
```

Optional GHCR login:

```bash
export GHCR_TOKEN='ghp_...'
export GHCR_USER='raghavendiran-2002'
./hack/pi/deploy-hubd-ci.sh
```

Check:

```bash
podman ps
curl -s http://127.0.0.1:8080/readyz
curl -s http://127.0.0.1:8080/healthz
podman logs sealhub-hubd | tail -30
```

---

## Install `hub` CLI on the Pi

```bash
cd ~/sealhub
go build -o hub ./cmd/hub
mkdir -p ~/.local/bin
mv hub ~/.local/bin/
grep -q '.local/bin' ~/.bashrc || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

Environment (add to `~/.bashrc`):

```bash
export SEALHUB_SERVER="http://127.0.0.1:8080"
export SEALHUB_TOKEN="your-bootstrap-token"
```

From another machine on the tailnet:

```bash
export SEALHUB_SERVER="http://live:8080"
# or http://100.72.63.104:8080
```

### CLI commands

| Action | Command |
|--------|---------|
| Get document | `hub get config/homelab/settings.yaml` |
| Get secret | `hub get secrets/homelab/sample.yaml` |
| List | `hub list secrets/homelab` |
| Create/update | `hub apply secrets/homelab/my.yaml -f ./my.yaml` |
| Delete | `hub delete secrets/homelab/my.yaml` |
| Watch | `hub watch secrets/homelab` |

API paths are **without** the `data/` prefix (Git stores under `data/config/...`, `data/secrets/...`).

Secrets under `secrets/...` are **encrypted** on apply; `config/...` stays plain YAML.

---

## Git commits from `hub apply`

hubd runs **`git commit`** inside the container against **`/var/lib/sealhub/repo`**. The repo needs **`user.name`** and **`user.email`**:

```bash
git -C /var/lib/sealhub/repo config user.name "SealHub Pi"
git -C /var/lib/sealhub/repo config user.email "sealhub@live"
```

Bootstrap and deploy scripts set this automatically. Newer **hubd** images also set identity on startup (`git.commitName` / `commitEmail` in config).

If apply fails with **Author identity unknown**, run the two `git config` lines above and retry.

---

## Example config (`/etc/sealhub/config.yaml`)

After bootstrap, structure matches:

```yaml
server:
  listen: ":8080"
  externalURL: "http://100.72.63.104:8080"

github:
  owner: Raghavendiran-2002
  repo: sealhub-data
  branch: main
  auth:
    type: ssh

git:
  localPath: /var/lib/sealhub/repo
  commitName: SealHub Pi
  commitEmail: sealhub@live

encryption:
  keyringFile: /run/secrets/keyring

auth:
  bootstrapToken: "<your-token>"
  jwtSecretFile: /run/secrets/jwt-secret

freshness:
  pollInterval: "30s"
```

Edit on host, then redeploy or restart so **`run/`** copies refresh:

```bash
./hack/pi/deploy-hubd-ci.sh
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|--------|-----|
| `open /config/config.yaml: permission denied` | Config not readable in container | chown `pi:pi`; use `run/` copies via deploy script |
| `keyring: open /etc/sealhub/keyring` | Wrong paths in config | Use `/run/secrets/keyring` in yaml; redeploy |
| `git commit: Author identity unknown` | No git user in repo | `git config user.name/email` on `/var/lib/sealhub/repo` |
| Port **8080 in use** | Stray `hubd` on host | `pkill -f hubd` or `ss -tlnp \| grep 8080`; restart container |
| `hub: command not found` | CLI not on PATH | `./hub` or install to `~/.local/bin` |
| CI: cannot read `/etc/sealhub/config.yaml` | `root:root` files, no sudo in CI | `PI_SUDO_PASS` in GitHub env **`tailscale`**, or chown on Pi once |
| GitHub push denied | SSH key | Ensure `pi`’s `~/.ssh` works for `git@github.com:.../sealhub-data.git` |

### Do not lose

- **`/etc/sealhub/keyring`** — without it, encrypted secrets cannot be decrypted.
- **Bootstrap token** — replaceable via config + restart; not the same as the keyring.

---

## CI deploy (summary)

1. **SealHub Image Build** → pushes `hubd:0.1-latest` to GHCR.
2. **SealHub Deploy Pi** (manual) → Tailscale WIF, **`ssh pi@live`**, runs `/tmp/deploy-hubd-ci.sh` + `/tmp/sync-run-config.sh`.

Secrets: **`TS_OAUTH_CLIENT_ID`**, **`TS_AUDIENCE`**, optional **`PI_SUDO_PASS`**, **`GHCR_READ_TOKEN`**.

Details: **[DEPLOY-CI.md](DEPLOY-CI.md)**.

---

## Related scripts

| Script | Use |
|--------|-----|
| [hack/pi/podman-setup.sh](../hack/pi/podman-setup.sh) | First-time install |
| [hack/pi/deploy-hubd-ci.sh](../hack/pi/deploy-hubd-ci.sh) | Pull image + restart |
| [hack/pi/sync-run-config.sh](../hack/pi/sync-run-config.sh) | Pi-owned config for Podman mounts |
| [hack/pi/install-sealhub.sh](../hack/pi/install-sealhub.sh) | Alternative: build hubd on Pi (dev) |

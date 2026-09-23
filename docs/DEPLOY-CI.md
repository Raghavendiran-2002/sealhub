# SealHub CI deploy to Pi (Tailscale SSH)

Workflow: [.github/workflows/deploy.yaml](../.github/workflows/deploy.yaml)

## Flow

1. **SealHub Image Build** pushes `ghcr.io/raghavendiran-2002/sealhub/hubd:0.1.<run>` and `:0.1-latest`.
2. **SealHub Deploy Pi** runs on `workflow_run` success (main only).
3. Runner joins **Tailscale** as an ephemeral node tagged **`tag:ci`**, then **`ssh pi@live`** (Tailscale SSH — no GitHub SSH key).

## GitHub environment: `tailscale`

Repository **Settings → Environments → tailscale** secrets:

| Secret | Purpose |
|--------|---------|
| `TS_OAUTH_CLIENT_ID` | Tailscale OAuth client for ephemeral CI nodes |
| `TS_OAUTH_SECRET` | Tailscale OAuth client secret |
| `GHCR_READ_TOKEN` | (Optional) PAT with `read:packages` if GHCR images are private |

**Not used:** `SSH_PRIVATE_KEY` — authentication is Tailscale SSH + ACLs.

## One-time: Tailscale on the Pi

On **`live`** (as a tailnet admin):

```bash
sudo tailscale set --ssh
```

Ensure MagicDNS resolves **`live`** (or set workflow to use the full `*.ts.net` name).

Recommended: tag the Pi (e.g. **`tag:homelab`**) in the admin console for clearer ACLs.

## One-time: ACL for CI → Pi

**Network `grants` and Tailscale `ssh` are separate.** A grant on port `22` only allows packets; SSH still needs an entry in the top-level **`ssh`** array.

Your Pi must be tagged **`tag:homelab`** (Machines → live → Edit route settings → Tags).

Create tag **`tag:ci`** in `tagOwners` (you already have this). The GitHub OAuth client must be allowed to assign **`tag:ci`** to ephemeral nodes.

### `grants` (you already have this — keep it)

```json
{
  "src": ["tag:ci"],
  "dst": ["tag:homelab"],
  "ip":  ["22"]
}
```

Optional: use `"ip": ["*"]` if you later need non-SSH traffic from CI to homelab.

### `ssh` (this is what was missing)

Replace or extend your **`ssh`** block. Keep your existing `autogroup:self` rule; **add** CI and (optional) homelab rules:

```json
"ssh": [
  {
    "action": "check",
    "src":    ["autogroup:member"],
    "dst":    ["autogroup:self"],
    "users":  ["autogroup:nonroot", "root"]
  },
  {
    "action": "accept",
    "src":    ["tag:ci"],
    "dst":    ["tag:homelab"],
    "users":  ["pi"]
  },
  {
    "action": "check",
    "src":    ["autogroup:member"],
    "dst":    ["tag:homelab"],
    "users":  ["pi"]
  }
]
```

| Rule | Why |
|------|-----|
| `tag:ci` → `tag:homelab`, **`accept`** | GitHub Actions (no browser for `check`) |
| `autogroup:member` → `tag:homelab`, **`check`** | Your laptop: `tailscale ssh pi@live` (re-auth in browser when prompted) |

**Why your test failed:** `tailscale ssh pi@100.72.63.104` from your Mac is **`autogroup:member` → `tag:homelab`**, not `autogroup:self`. The old policy only allowed SSH to **your own** nodes (`autogroup:self`), not tagged homelab hosts.

After saving ACLs, wait ~30s and retry:

```bash
tailscale ssh pi@100.72.63.104
# or
tailscale ssh pi@live
```

On the Pi, confirm SSH is advertised:

```bash
sudo tailscale set --ssh
tailscale status --json | jq '.Self.Tags, .Self.SSHHostKeys | length'
```

The client/tailscaled version mismatch warning is unrelated; upgrade Tailscale on the Mac when convenient.

## One-time on Pi (SealHub)

Run full bootstrap once (config, keyring, data clone):

```bash
./hack/pi/podman-setup.sh
```

CI deploy only **updates the hubd image** and restarts the container; it does not wipe `/etc/sealhub`.

## Manual deploy

**Actions → SealHub Deploy Pi → Run workflow**

- Default tag: `0.1-latest`
- Or set e.g. `0.1.5` to pin a build number.

## Host

- Tailscale IP: `100.72.63.104`
- MagicDNS short name: `live` (workflow falls back to the IP if `live` does not ping)

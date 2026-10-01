# Pi podman-compose stacks (SealHub: `data/live/podman-compose/`)

| Stack | Directory | Services |
|-------|-----------|----------|
| Pocket ID + Starry Cloud + Cloudflare tunnel | `pocket-id/` | `pocket-id`, `starry-cloud`, `cloudflared` |
| SealHub API | `sealhub-hubd/` | `hubd` |

No homelab DNS container — use Cloudflare tunnel + Tailscale for access as needed.

## Push to sealhub-data (Mac)

```bash
source ~/.config/sealhub/env
./hack/local/store-podman-compose-live.sh
```

## On Pi (`live`)

```bash
source ~/.config/sealhub/env
bash ~/sealhub/hack/pi/sync-podman-compose-from-sealhub.sh
cd ~/podman-compose/sealhub-hubd && podman-compose up -d   # or existing sealhub-hubd container
cd ~/pocket-id && podman compose up -d
```

Starry configs: `pocket-id/starry/config.yml` (SealHub) + `live/starry-cloud/auth.yml` (encrypted, synced to `~/pocket-id/starry/auth.yml`). Image on Pi: `starry-cloud:local`.

**Cloudflare tunnel** (token ingress on same compose network): Pocket ID → `http://pocket-id:1411` · Starry → `http://starry-cloud:5000`

Public Pocket ID: **https://id.raghavendiran.cloud** · Starry (example): **https://home.raghavendiran.cloud** · SealHub: **http://\<tailscale-or-lan\>:8080**

# Live node backup (`live/`)

Parent: [README.md](README.md).

## Scripts (branch `rootos`)

| Script | Runs on | Does |
|--------|---------|------|
| `hack/pi/backup-live-snapshot.sh` | **live** | Pocket ID env/db/key/data, RootOS config/auth, `_host` SSH |
| `hack/pi/backup-pocket-id-on-live.sh` | live | Pocket ID subset |
| `hack/pi/store-pi-ssh-tailscale.sh` | live | `live/_host/key/*`, tailscale |

```bash
export SEALHUB_SERVER=http://127.0.0.1:8080 SEALHUB_TOKEN=...
~/sealhub/hack/pi/backup-live-snapshot.sh
```

## Target paths (sealhub-data)

| App | Examples |
|-----|----------|
| `pocket-id` | `env/pocket-id.env`, `db/pocket-id.db`, `key/encryption.key`, `config/docker-compose.yaml` |
| `rootos` | `config/config.yml`, `secrets/auth.yml` |
| `cloudflare` | `secrets/token.txt` |
| `sealhub-hubd` | `config/docker-compose.yaml` |
| `_host` | `key/id_ed25519`, `secrets/tailscale-config` |

Use **`hub apply … -encrypt`** for secrets, env, db, key (on **live** hub build).

## Do not

- Reintroduce `live/starry-cloud/`, `live/podman-compose/`, `secrets/homelab/`.
- Use Mac `hub` for bulk `-encrypt` if the binary lacks the flag — use live.

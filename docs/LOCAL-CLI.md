# Local `hub` CLI (Mac / Linux dev machine)

Talk to hubd on the Pi over Tailscale or LAN.

## One-time setup

From the repo root:

```bash
chmod +x hack/local/setup-local-hub.sh
./hack/local/setup-local-hub.sh
```

This builds **`bin/hub`**, installs **`~/.local/bin/hub`**, and creates **`~/.config/sealhub/env`** (from the example if missing). `hack/local/sealhub.env` symlinks to that file when possible.

Edit the token if you changed bootstrap on the Pi:

```bash
$EDITOR ~/.config/sealhub/env
```

Default server in the example:

```bash
export SEALHUB_SERVER="http://100.72.63.104:8080"
```

Use **`http://live:8080`** instead if MagicDNS works on your tailnet.

## Every new terminal

New shells load **`~/.config/sealhub/env`** from `~/.bashrc` / `~/.zshrc` (added by setup). Or:

```bash
source ~/.config/sealhub/env
```

Then run **`hub`** (not `/opt/sealhub/hub` or `./bin/hub`).

## Pocket ID backup / restore

Production compose dir (Mac): set **`POCKET_ID_HOME`** in `sealhub.env` (see example).

| SealHub path | Content |
|--------------|---------|
| `pocket/homelab/pocket-id.db.yaml` | SQLite backup (YAML + base64, `pocket/` prefix) |
| `secrets/homelab/pocket-id.env` | Compose `.env` (encrypted) |

```bash
# Push live DB + .env to sealhub-data via Pi hubd (stops pocket-id briefly; raw DB copy matches on-disk size)
hub pocket backup
hub pocket backup -dir "$POCKET_ID_HOME" -instance homelab
# `-no-stop` uses sqlite3 .backup (smaller compact file; fine for same-host restore)

# Restore from hub into local compose dir (stops pocket-id briefly unless -no-stop)
hub pocket restore
hub pocket restore -dir "$POCKET_ID_HOME"
```

## Commands

```bash
hub get config/homelab/settings.yaml
hub get secrets/homelab/sample.yaml
hub list secrets/homelab
hub apply secrets/homelab/my.yaml -f ./my.yaml
```

Override server for one call:

```bash
hub -server http://100.72.63.104:8080 -token "$SEALHUB_TOKEN" get config/homelab/settings.yaml
```

## Requirements

- **Network** to the Pi (`curl http://100.72.63.104:8080/healthz` → `ok`)
- **Go 1.22+** to rebuild the CLI (`make build` or setup script)
- **Token** matching `auth.bootstrapToken` in Pi `/etc/sealhub/config.yaml`

`~/.config/sealhub/env` holds secrets — do not commit. `hack/local/sealhub.env` is gitignored when used as a local symlink/copy.

## Related

- Pi hubd setup: [PI-SETUP.md](PI-SETUP.md)

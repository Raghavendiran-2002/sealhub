---
name: sealhub-device-restore
description: >-
  Restores SealHub Pi from latest (or named) git snapshot in backups/device-live
  over SSH. Use when the user asks to restore SealHub, live Pi, device restore,
  or rollback podman/sealhub-data on the Pi.
---

# SealHub device restore

## Defaults

| Item | Value |
|------|--------|
| SSH | `pi@100.114.97.68` / `pi@live` |
| Latest snapshot | `backups/device-live/manifest.json` → `snapshots[0].id` |
| Script | `hack/pi/device-restore.sh` |

## Agent workflow

1. **Git pull** on sealhub repo so `backups/device-live/` is current (`up` workflows assume this too).
2. Confirm target snapshot (latest or user-provided `YYYY-MM-DDTHHMMSSZ`).
3. Run from repo root:

```bash
chmod +x hack/pi/device-restore.sh
export DEVICE_SSH=pi@100.114.97.68
export SEALHUB_TOKEN=…
bash hack/pi/device-restore.sh                    # latest
bash hack/pi/device-restore.sh 2026-11-12T063045Z # specific
```

4. Verify: `ssh pi@live 'curl -sf http://127.0.0.1:8080/healthz && podman ps'`

## GitHub Actions

Workflow **Device Restore (Pi live)** — optional input `snapshot_id` (empty = latest).

Setup: [docs/ci/device-backup-github-setup.md](../../docs/ci/device-backup-github-setup.md).

## Warning

Restore **replaces** `/var/lib/sealhub/repo` and `~/pocket-id` on the Pi from tarball. Confirm with user before running on production `live`.

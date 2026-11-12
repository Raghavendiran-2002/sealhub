---
name: sealhub-device-backup
description: >-
  Backs up SealHub Pi (podman on live / 100.114.97.68): quiesce containers,
  snapshot to sealhub-data device-live/ with 3-retention git, optional GitHub Actions.
  Use when the user asks to backup SealHub, live Pi, podman snapshot, or device-backup workflow.
---

# SealHub device backup

## Defaults

| Item | Value |
|------|--------|
| SSH | `pi@100.114.97.68` or `pi@live` (Tailscale) |
| Repo paths | `hack/pi/device-backup.sh` → **`sealhub-data/device-live/`** |
| Retention | 3 snapshots (`manifest.json`) |

## Agent workflow

1. Read [docs/device-backup-restore.md](../../docs/device-backup-restore.md) if behavior is unclear.
2. Ensure `SEALHUB_TOKEN` (optional) and SSH reachability (`DEVICE_SSH` / `LIVE_PASS`).
3. From **sealhub repo root**, run:

```bash
chmod +x hack/pi/device-backup.sh hack/pi/prune-device-backups.sh
export DEVICE_SSH=pi@100.114.97.68   # or pi@live
export SEALHUB_TOKEN=…             # optional hub pocket doc sync
bash hack/pi/device-backup.sh
```

4. Push when user asks: `git push` in **sealhub-data** after commit (local commit is automatic unless `DEVICE_BACKUP_GIT_COMMIT=0`).

## GitHub Actions

Workflow **Device Backup (Pi live)** (`workflow_dispatch`). Prerequisites: [docs/ci/device-backup-github-setup.md](../../docs/ci/device-backup-github-setup.md) (Tailscale WIF — same pattern as Kubernetes-Home-Lab homelab backup).

## Pi-side behavior (do not skip)

Snapshot script stops Pocket ID → optional `hub pocket backup` → stops `sealhub-hubd` → tars data → **restarts stacks** via `trap` on `device-snapshot-on-pi.sh`.

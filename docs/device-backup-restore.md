# Device backup and restore (Pi `live`)

Full **podman quiesced** snapshots of SealHub hubd data (`/var/lib/sealhub/repo`) and Pocket ID (`~/pocket-id`), stored in **[sealhub-data](https://github.com/Raghavendiran-2002/sealhub-data)** under **`device-live/`** with **3** retained snapshots (`YYYY-MM-DDTHHMMSSZ` UTC).

## Flow

1. **Stop** Pocket ID → optional `hub pocket backup` (hubd up) → stop hubd + tunnel sidecars.
2. **Tar** data dirs → copy to git tree → **prune** to 3 → **restart** podman stacks (trap on Pi script).

Restore inverts: stop → extract tarballs → start stacks → optional `hub pocket restore`.

## SSH (local agent)

Default: **`pi@100.114.97.68`** (Tailscale). Override:

```bash
export DEVICE_SSH=pi@live
export SEALHUB_TOKEN=…          # Pi bootstrap/service token
export LIVE_PASS=…              # optional; prefer Tailscale SSH keys
# Default: ../sealhub-data/device-live (override with DEVICE_BACKUP_ROOT)
export DEVICE_BACKUP_GIT_COMMIT=1   # commit in sealhub-data clone after backup
bash hack/pi/device-backup.sh
bash hack/pi/device-restore.sh
bash hack/pi/device-restore.sh 2026-11-12T063045Z
```

## GitHub Actions

- **Device Backup (Pi live)** — `workflow_dispatch`
- **Device Restore (Pi live)** — optional `snapshot_id` (default: latest in `manifest.json`)

Setup: [ci/device-backup-github-setup.md](ci/device-backup-github-setup.md) (same Tailscale WIF pattern as [Kubernetes-Home-Lab](https://github.com/Raghavendiran-2002/Kubernetes-Home-Lab) private backup + SealHub deploy).

## vs sealhub-data API backups

`hub pocket backup` still updates encrypted documents in **sealhub-data**. Device snapshots add **offline** recovery (entire git working copy + Pocket tree) when hubd or disk state is broken.

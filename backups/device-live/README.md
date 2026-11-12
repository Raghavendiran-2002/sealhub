# Device backups (`live` / `100.114.97.68`)

Git source of truth for **full Pi snapshots** (podman quiesced). **Retention: 3** timestamped directories.

| Path | Contents |
|------|----------|
| `manifest.json` | Ordered snapshot ids (newest first) |
| `YYYY-MM-DDTHHMMSSZ/` | `metadata.json`, `sealhub-repo.tar.gz`, `pocket-id-home.tar.gz`, optional `etc-sealhub/` |

**Local**

```bash
export SEALHUB_TOKEN=…   # optional hub pocket doc backup during snapshot
bash hack/pi/device-backup.sh
bash hack/pi/device-restore.sh              # latest
bash hack/pi/device-restore.sh 2026-11-12T120000Z
```

**GitHub Actions** — workflow_dispatch: `Device Backup (Pi live)` / `Device Restore (Pi live)`.

See [docs/device-backup-restore.md](../docs/device-backup-restore.md) and [docs/ci/device-backup-github-setup.md](../docs/ci/device-backup-github-setup.md).

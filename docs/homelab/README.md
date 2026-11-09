# Pi and edge operations

Parent: [overview.md](../overview.md). Path rules: [sealhub-data layout](https://github.com/Raghavendiran-2002/sealhub-data/blob/main/docs/layout.md).

| Doc | When |
|-----|------|
| [pi-setup.md](pi-setup.md) | First-time hubd + Podman + CLI on **`live`** |
| [live-backup.md](live-backup.md) | Snapshot Pocket ID, RootOS, `_host` → sealhub-data |
| [k8s-backup.md](k8s-backup.md) | Control plane exports → `rpi-control-plane/` |
| [restore.md](restore.md) | New Pi, keyring copy, manual restore from git |
| [deploy.md](deploy.md) | `podman-setup.sh`, RootOS deploy scripts |

**Normalize paths after layout change:** `hack/data/normalize-sealhub-data.sh` on **live**.

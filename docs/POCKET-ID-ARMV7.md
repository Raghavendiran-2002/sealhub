# Pocket ID image for linux/arm/v7 (Pi 32-bit)

Upstream [Pocket ID](https://github.com/pocket-id/pocket-id) publishes Docker images for **linux/amd64** and **linux/arm64** only. A **32-bit Raspberry Pi OS** (`armv7l`) cannot pull `ghcr.io/pocket-id/pocket-id`.

SealHub provides an **optional** GitHub Actions workflow that:

1. Clones **upstream Pocket ID at a release tag** (no Pocket ID source in the sealhub repo).
2. Builds the frontend and cross-compiles the Go binary for **`GOOS=linux GOARCH=arm GOARM=7`**.
3. Packages with upstream **`docker/Dockerfile-prebuilt`**.
4. Pushes to **GHCR** under this repo’s package namespace.

## Run the workflow

**Actions → Pocket ID armv7 image → Run workflow**

| Input | Meaning |
|--------|---------|
| **run** | `true` = build and push; `false` = skip (job prints a message only). |
| **pocket_id_tag** | Release tag from [Pocket ID releases](https://github.com/pocket-id/pocket-id/releases), e.g. `v2.14.0`. |

## Image tags

After a successful run (example tag `v2.14.0`):

- `ghcr.io/raghavendiran-2002/sealhub/pocket-id:v2.14.0-armv7`
- `ghcr.io/raghavendiran-2002/sealhub/pocket-id:2.14.0-armv7`
- `ghcr.io/raghavendiran-2002/sealhub/pocket-id:armv7-latest`

Make the package **public** (or log in with a PAT) on the Pi before `podman pull`.

## Use on Pi

```bash
podman pull ghcr.io/raghavendiran-2002/sealhub/pocket-id:v2.14.0-armv7
# ~/pocket-id/.env and data/ from hub pocket restore
cd ~/pocket-id
podman run -d --name pocket-id --replace \
  -p 1411:1411 \
  --env-file .env \
  -e 'DB_CONNECTION_STRING=file:data/pocket-id.db?_journal_mode=DELETE' \
  -v "$PWD/data:/app/data:Z" \
  ghcr.io/raghavendiran-2002/sealhub/pocket-id:v2.14.0-armv7
```

## Notes

- **Unofficial** arm/v7 rebuild — not maintained by the Pocket ID project. Use the same license (BSD-2-Clause) and track upstream releases.
- Builds require the **Go version** in upstream `backend/go.mod` (workflow uses `setup-go` with that file).
- First build can take **15–30+ minutes** (pnpm + cross-compile + QEMU arm/v7 image layer).

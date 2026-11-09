# AGENTS.md — SealHub

**SealHub** = Git-backed secrets/config hub: **`hubd`** (API + git push), **`hub`** (CLI), optional **HubPull** operator. Homelab runs hubd on **`live`**; documents live in private repo **sealhub-data**.

**Read first:** [docs/README.md](docs/README.md) → [docs/overview.md](docs/overview.md) → one branch: [docs/homelab/README.md](docs/homelab/README.md), [docs/product/README.md](docs/product/README.md), [docs/dev/README.md](docs/dev/README.md), or [docs/ci/README.md](docs/ci/README.md). **sealhub-data:** [AGENTS.md](https://github.com/Raghavendiran-2002/sealhub-data/blob/main/AGENTS.md)

## Commands

| Task | Command |
|------|---------|
| Build CLI + hubd | `make build` → `bin/hub`, `bin/hubd` |
| Tests | `make test` |
| List docs (live hubd) | `SEALHUB_SERVER=http://100.114.97.68:8080 SEALHUB_TOKEN=... bin/hub list live/` |
| Apply encrypted secret | `hub apply live/rootos/secrets/auth.yml -f auth.yml -encrypt` (**use hub on live** or a build with `-encrypt`; Mac CLI may lag) |
| Normalize sealhub-data layout | On **live**: `bash hack/data/normalize-sealhub-data.sh` |
| Live snapshot | On **live**: `SEALHUB_TOKEN=... hack/pi/backup-live-snapshot.sh` |
| K8s backup → hub | `hack/k8s/store-rpi-control-plane-to-sealhub.sh` (from Mac; `RPI_DATA` or SSH) |
| RootOS deploy | Branch **`rootos`**: `METRICS_TOKEN=... hack/pi/deploy-rootos-all.sh` |

**Branches:** `main` = Go hub/hubd/operator + Pi **main** scripts. `rootos` = RootOS Rust dashboard + homelab backup/deploy scripts (does not replace `main` for hubd).

## Repository map

| Path | Purpose | Edit? |
|------|---------|-------|
| `cmd/hub/`, `cmd/hubd/` | CLI and server | **Yes** (feature work on `main`) |
| `pkg/`, `internal/` | Store, crypto, auth, pocket backup | **Yes** |
| `operator/` | HubPull CRD/controller | **Yes** |
| `deploy/` | Operator/hubd K8s samples | **Yes** |
| `docs/` | Product and ops docs (this repo only) | **Yes** |
| `hack/k8s/` | Collect/store control-plane backups | **Yes** — align paths with **sealhub-data** |
| `hack/pi/` | Pi install, backup, RootOS deploy (`rootos`) | **Yes** on active branch |
| `hack/data/normalize-sealhub-data.sh` | One-shot layout migration | Run on live; update if path standard changes |
| `app/` | RootOS Rust app | **`rootos` branch only** |
| `hack/pi/starry-cloud/`, `deploy-starry-cloud-*` | Legacy Starry Cloud | **Avoid** — use RootOS paths |

Deep design: [docs/product/design.md](docs/product/design.md). Pi install: [docs/homelab/pi-setup.md](docs/homelab/pi-setup.md).

## sealhub-data

| API path | File on disk |
|----------|----------------|
| `live/pocket-id/env/pocket-id.env` | `sealhub-data/data/live/pocket-id/env/pocket-id.env` |

Path standard: `<node>/<application>/{config,secrets,env,db,key}/` — nodes `live`, `rpi-control-plane`. See sealhub-data README.

## Conventions

- **Encrypt:** namespace `secrets/secrets.yaml` dumps with `-encrypt`; **SealedSecret** files with `-no-encrypt` at envelope.
- **Never** commit `config.yaml` with real `github` deploy keys or production `keyring` into this repo.

## Boundaries — do not

- Push to **sealhub-data** by editing YAML envelopes locally without `hub apply` (breaks metadata/version).
- Change hubd `keyring` on live without user migration plan (orphans encrypted docs).
- Remove `-encrypt` from backup scripts for Secret dumps or live `env`/`key`/`db` paths.
- Commit bootstrap tokens or real `SEALHUB_TOKEN` values.

## When done

- If paths change: update **sealhub-data** docs and the **normalize** script.
- If adding backup types: extend `store-rpi-control-plane-to-sealhub.sh` encrypt rules and document in sealhub-data.

# SealHub overview

**SealHub** = `hubd` (API + git push), `hub` (CLI), optional HubPull **operator**. Encrypted documents live in the private git repo **sealhub-data** (`data/<path>` on disk).

```text
operators ──hub apply/get──► hubd ──push──► sealhub-data (GitHub)
                ▲
           live / other nodes
```

## Repositories (this workspace)

| Repo | Role |
|------|------|
| **sealhub** (here) | Source code, `hack/pi`, `hack/k8s`, operator samples |
| **sealhub-data** | Document envelopes only — use `hub apply`, do not hand-edit |

Other homelab automation (cluster GitOps, Ansible) lives in **separate** checkouts; not documented in this repo.

## Branches

| Branch | Use |
|--------|-----|
| `main` | hubd, hub CLI, operator, default Pi install scripts |
| `rootos` | RootOS app, `deploy-rootos-*`, `backup-live-snapshot.sh`, `hack/k8s` |

hubd on **live** may run `main` images; use **`rootos`** for latest backup/deploy scripts.

## API path prefixes (nodes)

| Prefix | Typical host | Scripts in this repo |
|--------|--------------|----------------------|
| `live/` | Edge / hubd host | `hack/pi/backup-live-snapshot.sh`, `hack/pi/podman-setup.sh` |
| `rpi-control-plane/` | Kubernetes control plane | `hack/k8s/*` collect/store |

Layout: `<node>/<app>/{config,secrets,env,db,key}/`. Authoritative: [sealhub-data docs/layout.md](https://github.com/Raghavendiran-2002/sealhub-data/blob/main/docs/layout.md).

## Next doc (pick one)

| Task | Doc |
|------|-----|
| Install hubd, Podman, bootstrap | [homelab/pi-setup.md](homelab/pi-setup.md) |
| Backup `live/` or `rpi-control-plane/` | [homelab/README.md](homelab/README.md) |
| New Pi + keyring | [homelab/restore.md](homelab/restore.md) |
| Crypto / envelope schema | [product/design.md](product/design.md) |

## Boundaries

- Do not store application GitOps manifests only in sealhub-data — that is not this product’s job.
- Do not edit `data/**` YAML envelopes locally without `hub apply`.
- Retired API paths: `live/starry-cloud/`, `live/podman-compose/`, `secrets/homelab/` (use `live/...` standard).

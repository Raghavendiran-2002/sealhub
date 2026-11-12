# SealHub

Lightweight Git-backed secrets and configuration hub: **hubd** (API), **hub** (CLI), and a Kubernetes **HubPull** operator.

**Coding agents:** [AGENTS.md](AGENTS.md) · Docs hub: [docs/README.md](docs/README.md)

- Documents stored in GitHub with envelope encryption
- OIDC (CLI) + service tokens
- SSE change stream for watches
- Multi-arch container images (amd64, arm64, arm/v7)

**Overview:** [docs/overview.md](docs/overview.md). **Pi hubd:** [docs/homelab/pi-setup.md](docs/homelab/pi-setup.md) · **Restore:** [docs/homelab/restore.md](docs/homelab/restore.md) · **Device backup/restore (Pi):** [docs/device-backup-restore.md](docs/device-backup-restore.md) · **Local CLI:** [docs/dev/local-cli.md](docs/dev/local-cli.md) · **Design:** [docs/product/design.md](docs/product/design.md) · **CI:** [docs/ci/deploy.md](docs/ci/deploy.md).

## Build

```bash
make build
make test
```

## Quick start (dev)

```bash
cp config/example.yaml config.yaml
# fill github + secrets paths
./bin/hubd config.yaml
SEALHUB_TOKEN=... ./bin/hub list
```

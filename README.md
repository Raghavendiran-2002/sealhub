# SealHub

Lightweight Git-backed secrets and configuration hub: **hubd** (API), **hub** (CLI), and a Kubernetes **HubPull** operator.

- Documents stored in GitHub with envelope encryption
- OIDC (CLI) + service tokens
- SSE change stream for watches
- Multi-arch container images (amd64, arm64, arm/v7)

See [docs/DESIGN.md](docs/DESIGN.md). **Raspberry Pi:** [docs/PI-SETUP.md](docs/PI-SETUP.md). **Local CLI → Pi:** [docs/LOCAL-CLI.md](docs/LOCAL-CLI.md). **CI deploy:** [docs/DEPLOY-CI.md](docs/DEPLOY-CI.md). **Pocket ID armv7 image:** [docs/POCKET-ID-ARMV7.md](docs/POCKET-ID-ARMV7.md).

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

# SealHub design

## Document paths

- API paths are relative to namespace `data` (default).
- Git file: `data/{apiPath}` — e.g. API `secrets/team-ns/app.yaml` → `data/secrets/team-ns/app.yaml`.
- **Pocket ID:** `pocket/{instance}/pocket-id.db.yaml` (plain backup blob); `secrets/{instance}/pocket-id.env` (encrypted env).
- **Pi host (`live`):** `live/ssh/id_ed25519`, `live/ssh/id_ed25519.pub`, `live/tailscale/config` → `data/live/...` (use `hub apply -encrypt` for key material).
- **K8s control plane (`rpi4-control-plane`):** `rpi-control-plane/ssh/id_ed25519`, `rpi-control-plane/ssh/id_ed25519.pub` → `data/rpi-control-plane/ssh/...` (private key encrypted).
- **K8s control plane (`rpi4-control-plane`):** `rpi-control-plane/<app>/config/*`, `rpi-control-plane/<app>/secrets/*`, `rpi-control-plane/_cluster/credentials/*`, `rpi-control-plane/_cluster/oidc/*` → `data/rpi-control-plane/...` (encrypt secrets, credentials, and OIDC client material).
- System documents live under `system/` (issuers, tokens) and are not exposed via the public document API unless admin.

## Envelope (schema 1)

```yaml
schema: 1
metadata:
  version: 1          # optimistic lock; 1 on create
  contentType: application/json | application/yaml | text/plain
  encrypted: false
  labels: {}
  owner: ""           # oidc:{iss}:{sub} or token:{id}
document: |           # plaintext in API; ciphertext string when encrypted
  ...
```

When `metadata.encrypted` is true, `document` holds standard base64 of `nonce || ciphertext` (AES-256-GCM).

## Encryption wire format

- Algorithm: AES-256-GCM.
- Key ring: newline-delimited base64 32-byte keys; first line is primary.
- Plaintext is UTF-8 bytes of the document body string before YAML envelope nesting.

## Service tokens

Stored in `system/tokens.yaml` (envelope with list of token records). Each record: `id`, `hash` (bcrypt), `scopes.paths`, `scopes.actions` (`read`, `write`).

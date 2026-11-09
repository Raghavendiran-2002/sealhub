# SealHub product internals

For deployment and backup, start at [overview.md](../overview.md) — not here.

| Doc | When |
|-----|------|
| [design.md](design.md) | Envelope schema, encryption, tokens, API path rules |

**Homelab path layout** (current): sealhub-data [docs/layout.md](https://github.com/Raghavendiran-2002/sealhub-data/blob/main/docs/layout.md) — overrides legacy examples in design.md.

**Code:** `pkg/document/`, `pkg/crypto/`, `pkg/store/`, `cmd/hubd/`, `cmd/hub/`.

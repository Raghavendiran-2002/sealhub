# Tailscale WIF for SealHub deploy (GitHub Actions)

Same model as homelab `docs/agents/tailscale-oidc-ci.md`: GitHub OIDC → **Trust credential** → ephemeral node `tag:ci` → Tailscale SSH to `tag:homelab`.

## Before first deploy — Tailscale Trust credential (SealHub)

Create a **separate** credential from homelab (different repo → different Subject).

1. [Trust credentials](https://login.tailscale.com/admin/settings/trust-credentials) → **Add credential** → **GitHub Actions** (OpenID Connect).

| Field | Value |
|--------|--------|
| **Description** | `SealHub` |
| **Scope** | `auth_keys` |
| **Tags on credential** | **`tag:ci` only** (do not add `tag:homelab`) |
| **Subject** | See below |

### Subject (static — set once)

Workflow uses `environment: tailscale`, so GitHub sends a subject with **`environment:tailscale`**. Use the **exact** string Tailscale shows after one failed run, or this value if it matches your repo:

```text
repo:Raghavendiran-2002@70228368/sealhub@1382946894:environment:tailscale
```

Do **not** use `repo:Raghavendiran-2002/sealhub:environment:tailscale` unless Tailscale’s “Received … from issuer” line shows that short form (GitHub usually includes `@ownerId` and `@repoId`).

Optional broader patterns (only if Tailscale accepts them for your tailnet):

| Subject | Use when |
|---------|----------|
| `repo:Raghavendiran-2002@70228368/sealhub@1382946894:environment:tailscale` | Recommended (matches OIDC `sub`) |
| `repo:Raghavendiran-2002/sealhub:environment:tailscale` | Only if issuer sends this exact string |

### GitHub environment `tailscale` secrets

From **this** trust credential’s detail page (not Settings → OAuth clients):

| Tailscale field | GitHub secret | Example shape |
|-----------------|---------------|-----------------|
| **Client ID** | `TS_OAUTH_CLIENT_ID` | `TNiNGJXpzB21CNTRL-…` |
| **Audience** | `TS_AUDIENCE` | `api.tailscale.com/TNiNGJXpzB21CNTRL-…` |

No trailing spaces. **Do not** put Audience into `TS_NODE_AUTHKEY`.

Homelab’s `TS_OAUTH_CLIENT_ID` / `TS_AUDIENCE` on environment `homelab` are **not** valid for SealHub unless you create one credential whose Subject covers both repos (unusual).

## ACL (same tailnet as homelab)

Ensure `ssh` allows `tag:ci` → `tag:homelab` as user `pi`, and `grants` allow port 22. Pi tagged `tag:homelab`, `sudo tailscale set --ssh`.

## Workflow

See [.github/workflows/deploy.yaml](../.github/workflows/deploy.yaml): `id-token: write`, `tailscale/github-action@v4` with `oauth-client-id` + `audience` + `tags: tag:ci`.

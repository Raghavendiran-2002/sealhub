# GitHub Actions → Pi SSH (device backup/restore)

Same approach as **[Kubernetes-Home-Lab `.github/workflows/private-backup.yml`](https://github.com/Raghavendiran-2002/Kubernetes-Home-Lab)** and **[SealHub deploy](tailscale-oidc.md)**:

1. **OIDC** `id-token: write` on the workflow.
2. **Tailscale Trust credential** (WIF) scoped to this repo + `environment:tailscale`.
3. **`tailscale/github-action@v4`** joins the runner with **`tag:ci`**.
4. **Tailscale SSH** to the Pi as **`pi`** (`pi@live` or `pi@100.114.97.68`).

## One-time Tailscale setup

| Step | Action |
|------|--------|
| Trust credential | [Tailscale admin → Trust credentials](https://login.tailscale.com/admin/settings/trust-credentials) → GitHub Actions OIDC |
| Tags on credential | **`tag:ci` only** |
| Subject | `repo:Raghavendiran-2002@<ownerId>/sealhub@<repoId>:environment:tailscale` (copy from a failed OIDC log if needed) |
| Pi | Tag **`tag:homelab`**, run `sudo tailscale set --ssh` |

### ACL (tailnet)

Allow runner nodes with `tag:ci` to SSH as `pi` to `tag:homelab` (same as homelab CI). See Kubernetes-Home-Lab `infrastructure` docs for the `ssh` policy block.

## GitHub `environment: tailscale` secrets

| Secret | Source |
|--------|--------|
| `TS_OAUTH_CLIENT_ID` | Trust credential **Client ID** |
| `TS_AUDIENCE` | Trust credential **Audience** (`api.tailscale.com/…`) |
| `SEALHUB_PI_BACKUP_TOKEN` | Pi `hub` token (e.g. bootstrap token in `/etc/sealhub/config.yaml`) — for optional `hub pocket` during snapshot |
| `PI_SUDO_PASS` | Optional; only if restore needs `sudo` without NOPASSWD |

Do **not** put Audience into Client ID or use homelab’s `environment:homelab` credential unless Subject covers this repo.

## Homelab vs SealHub credentials

| Repo | GitHub environment | Subject ends with |
|------|-------------------|-------------------|
| Kubernetes-Home-Lab | `homelab` | `environment:homelab` |
| sealhub (deploy + backup) | `tailscale` | `environment:tailscale` |

Create **separate** trust credentials unless one Subject intentionally spans both.

## Workflows

| Workflow | Action |
|----------|--------|
| [device-backup.yml](../../.github/workflows/device-backup.yml) | SSH → snapshot → commit `backups/device-live/` → push |
| [device-restore.yml](../../.github/workflows/device-restore.yml) | SSH → upload latest (or input) snapshot → restore |

Composite action: [.github/actions/connect-tailscale-pi](../../.github/actions/connect-tailscale-pi/action.yml).

## Verify locally (no Actions)

```bash
ssh -o BatchMode=yes pi@100.114.97.68 true
# or after tailscale up on your Mac:
ssh pi@live true
```

Then run `hack/pi/device-backup.sh` from the sealhub clone.

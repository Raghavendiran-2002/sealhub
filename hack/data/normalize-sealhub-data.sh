#!/usr/bin/env bash
# Reorganize sealhub-data to node/app/category layout; delete samples; fix encryption.
# Run on live (hubd + repo at /var/lib/sealhub/repo) or Mac against live hubd:
#   SEALHUB_TOKEN=... bash hack/data/normalize-sealhub-data.sh
set -euo pipefail

export SEALHUB_SERVER="${SEALHUB_SERVER:-http://127.0.0.1:8080}"
[[ -n "${SEALHUB_TOKEN:-}" ]] || { echo "Set SEALHUB_TOKEN" >&2; exit 1; }
command -v hub >/dev/null || { echo "hub not on PATH" >&2; exit 1; }

REPO_ROOT="${SEALHUB_REPO_ROOT:-/var/lib/sealhub/repo}"
DATA="${REPO_ROOT}/data"

hub_delete() {
  local path="$1"
  if hub get "$path" -o json >/dev/null 2>&1; then
    echo "delete $path" >&2
    hub delete "$path" 0 >/dev/null 2>&1 || hub delete "$path" >/dev/null 2>&1 || true
  fi
}

extract_doc() {
  python3 - "$1" <<'PY'
import pathlib, sys, yaml
p = pathlib.Path(sys.argv[1])
raw = p.read_text()
data = yaml.safe_load(raw)
if not isinstance(data, dict):
    sys.exit(f"not an envelope: {p}")
doc = data.get("document")
if doc is None:
    sys.exit(f"no document: {p}")
out = doc if isinstance(doc, str) else yaml.dump(doc, default_flow_style=False)
pathlib.Path("/tmp/sealhub-normalize-doc").write_text(out)
PY
}

hub_migrate() {
  local from="$1" to="$2" enc="$3"
  local git_from="${DATA}/${from}"
  [[ -f "$git_from" ]] || { echo "skip missing $from" >&2; return 0; }
  # e.g. live/pocket-id/db (file) blocks live/pocket-id/db/pocket-id.db (directory)
  if [[ "$to" == */db/* ]] && [[ -f "${DATA}/${to%%/db/*}/db" ]]; then
    hub_delete "${to%%/db/*}/db"
  fi
  extract_doc "$git_from"
  echo "apply $to ($enc)" >&2
  hub apply "$to" -f /tmp/sealhub-normalize-doc "$enc" >/dev/null
  hub_delete "$from"
}

reencrypt_file() {
  local api="$1"
  local git_f="${DATA}/${api}"
  [[ -f "$git_f" ]] || return 0
  if grep -q 'encrypted: true' "$git_f" 2>/dev/null; then
    return 0
  fi
  extract_doc "$git_f"
  echo "re-encrypt $api" >&2
  hub apply "$api" -f /tmp/sealhub-normalize-doc -encrypt >/dev/null
}

echo "==> Migrate live paths to node/app/category" >&2
hub_migrate "live/starry-cloud/config.yml" "live/rootos/config/config.yml" "-no-encrypt"
hub_migrate "live/starry-cloud/auth.yml" "live/rootos/secrets/auth.yml" "-encrypt"
hub_migrate "live/podman-compose/pocket-id/docker-compose.yaml" "live/pocket-id/config/docker-compose.yaml" "-no-encrypt"
hub_migrate "live/podman-compose/sealhub-hubd/docker-compose.yaml" "live/sealhub-hubd/config/docker-compose.yaml" "-no-encrypt"
hub_migrate "live/podman-compose/sealhub-hubd/.env.example" "live/sealhub-hubd/config/.env.example" "-no-encrypt"
hub_migrate "live/podman-compose/pocket-id/.env.example" "live/pocket-id/config/.env.example" "-no-encrypt"
hub_migrate "live/cloudflare/token.txt" "live/cloudflare/secrets/token.txt" "-encrypt"
hub_migrate "live/pocket-id/encryption.key" "live/pocket-id/key/encryption.key" "-encrypt"
hub_migrate "live/pocket-id/db" "live/pocket-id/db/pocket-id.db" "-encrypt"
hub_migrate "live/ssh/id_ed25519" "live/_host/key/id_ed25519" "-encrypt"
hub_migrate "live/ssh/id_ed25519.pub" "live/_host/config/id_ed25519.pub" "-no-encrypt"
hub_migrate "live/tailscale/config" "live/_host/secrets/tailscale-config" "-encrypt"
hub_migrate "secrets/homelab/pocket-id.env" "live/pocket-id/env/pocket-id.env" "-encrypt"

echo "==> Remove legacy / sample documents" >&2
for stale in \
  config/homelab/settings.yaml \
  secrets/homelab/sample.yaml \
  secrets/homelab/sgs.yaml \
  pocket/homelab/pocket-id.db.yaml \
  live/starry-cloud/docker-compose.yml \
  live/starry-cloud/config.yml \
  live/starry-cloud/auth.yml \
  live/podman-compose/pocket-id/docker-compose.yaml \
  live/podman-compose/pocket-id/starry/config.yml \
  live/podman-compose/pocket-id/.env.example \
  live/podman-compose/sealhub-hubd/docker-compose.yaml \
  live/podman-compose/sealhub-hubd/.env.example \
  live/cloudflare/token.txt \
  live/pocket-id/encryption.key \
  live/pocket-id/db \
  live/ssh/id_ed25519 \
  live/ssh/id_ed25519.pub \
  live/tailscale/config \
  secrets/homelab/pocket-id.env; do
  hub_delete "$stale"
done

echo "==> Re-encrypt rpi-control-plane Secret dumps" >&2
while IFS= read -r f; do
  rel="${f#"${DATA}/"}"
  reencrypt_file "$rel"
done < <(find "${DATA}/rpi-control-plane" -path '*/secrets/secrets.yaml' -type f 2>/dev/null | sort)

for cred in \
  rpi-control-plane/_cluster/credentials/admin.conf \
  rpi-control-plane/_cluster/credentials/kubeconfig-pi.yaml \
  rpi-control-plane/_cluster/oidc/kubernetes-oidc.yaml \
  rpi-control-plane/_cluster/oidc/kubeconfig-oidc.yaml; do
  reencrypt_file "$cred"
done

reencrypt_file "live/rootos/secrets/auth.yml"

rm -f /tmp/sealhub-normalize-doc
echo "Done. git pull sealhub-data on your Mac." >&2

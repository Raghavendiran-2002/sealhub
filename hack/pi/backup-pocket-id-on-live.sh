#!/usr/bin/env bash
# Run ON hostname live: backup Pocket ID into sealhub-data (homelab + live/ paths).
set -euo pipefail

POCKET_ID_HOME="${POCKET_ID_HOME:-$HOME/pocket-id}"
# Default: stop pocket-id for a quiesced DB + readable data/ (set POCKET_BACKUP_STOP=0 to skip).
POCKET_BACKUP_STOP="${POCKET_BACKUP_STOP:-1}"
export SEALHUB_SERVER="${SEALHUB_SERVER:-http://127.0.0.1:8080}"

if [[ -z "${SEALHUB_TOKEN:-}" ]]; then
  echo "Set SEALHUB_TOKEN (e.g. source ~/.config/sealhub/env)" >&2
  exit 1
fi

command -v hub >/dev/null || { echo "hub not on PATH" >&2; exit 1; }

ENV_PATH="${POCKET_ID_HOME}/.env"
DATA_DIR="${POCKET_ID_HOME}/data"
DB_PATH="${DATA_DIR}/pocket-id.db"
if [[ ! -f "$ENV_PATH" ]] || [[ ! -f "$DB_PATH" ]]; then
  echo "missing $ENV_PATH or $DB_PATH" >&2
  exit 1
fi

BACKUP_HOME="$POCKET_ID_HOME"
STAGE=""
tmp=""
POCKET_WAS_RUNNING=false

start_pocket_if_stopped() {
  if [[ "$POCKET_BACKUP_STOP" != "1" ]] || [[ "$POCKET_WAS_RUNNING" != "true" ]]; then
    return 0
  fi
  echo "starting pocket-id..." >&2
  if [[ -f "${POCKET_ID_HOME}/docker-compose.yaml" ]] || [[ -f "${POCKET_ID_HOME}/docker-compose.yml" ]]; then
    (cd "$POCKET_ID_HOME" && podman compose up -d pocket-id) 2>/dev/null \
      || (cd "$POCKET_ID_HOME" && podman-compose up -d pocket-id) 2>/dev/null \
      || podman start pocket-id 2>/dev/null || true
  else
    podman start pocket-id 2>/dev/null || true
  fi
}

cleanup() {
  start_pocket_if_stopped
  [[ -n "${tmp:-}" && -f "$tmp" ]] && rm -f "$tmp"
  [[ -n "$STAGE" && -d "$STAGE" ]] && rm -rf "$STAGE"
}
trap cleanup EXIT

if [[ "$POCKET_BACKUP_STOP" == "1" ]]; then
  if podman inspect pocket-id --format '{{.State.Running}}' 2>/dev/null | grep -q true; then
    POCKET_WAS_RUNNING=true
    echo "stopping pocket-id..." >&2
    if [[ -f "${POCKET_ID_HOME}/docker-compose.yaml" ]] || [[ -f "${POCKET_ID_HOME}/docker-compose.yml" ]]; then
      (cd "$POCKET_ID_HOME" && podman compose stop pocket-id) 2>/dev/null \
        || (cd "$POCKET_ID_HOME" && podman-compose stop pocket-id) 2>/dev/null \
        || podman stop pocket-id
    else
      podman stop pocket-id
    fi
    sleep 2
  fi
fi

sudo_cp() {
  if sudo -n true 2>/dev/null; then
    sudo cp "$@"
  elif [[ -n "${SUDO_PASS:-}" ]]; then
    printf '%s\n' "$SUDO_PASS" | sudo -S cp "$@"
  else
    sudo cp "$@"
  fi
}
sudo_chown() {
  if sudo -n true 2>/dev/null; then
    sudo chown "$@"
  elif [[ -n "${SUDO_PASS:-}" ]]; then
    printf '%s\n' "$SUDO_PASS" | sudo -S chown "$@"
  else
    sudo chown "$@"
  fi
}

needs_stage=false
if [[ ! -r "$DB_PATH" ]]; then
  needs_stage=true
fi
if [[ -d "${DATA_DIR}/uploads" ]] && ! find "${DATA_DIR}/uploads" -type f -readable -print -quit 2>/dev/null | grep -q .; then
  needs_stage=true
fi
# WAL/SHM often container-owned while Pocket ID is running
for aux in pocket-id.db-shm pocket-id.db-wal; do
  if [[ -f "${DATA_DIR}/${aux}" ]] && [[ ! -r "${DATA_DIR}/${aux}" ]]; then
    needs_stage=true
  fi
done

if $needs_stage || [[ "$POCKET_WAS_RUNNING" == "true" ]]; then
  STAGE="$(mktemp -d)"
  mkdir -p "${STAGE}/data"
  echo "staging ${DATA_DIR} (sudo)..." >&2
  sudo_cp -a "${DATA_DIR}/." "${STAGE}/data/"
  sudo_cp "$ENV_PATH" "${STAGE}/.env"
  sudo_chown -R "$(id -u):$(id -g)" "$STAGE"
  BACKUP_HOME="$STAGE"
fi

echo "Pocket ID backup (pocket/ + secrets/homelab/)..." >&2
# Stop/start is handled above; staged dir has no compose file for hub's compose stop.
hub pocket backup -dir "$BACKUP_HOME" -no-stop

# shellcheck disable=SC1090
set -a
source "${BACKUP_HOME}/.env"
set +a

tmp="$(mktemp)"

hub apply live/pocket-id/encryption.key -f <(printf '%s\n' "$ENCRYPTION_KEY") -encrypt >/dev/null
DB_APPLY="${BACKUP_HOME}/data/pocket-id.db"
hub apply live/pocket-id/db -f "$DB_APPLY" -encrypt >/dev/null

echo "Pocket ID data tree → live/pocket-id/data/..." >&2
while IFS= read -r f; do
  rel="${f#"${BACKUP_HOME}/data"/}"
  rel="${rel#/}"
  api="live/pocket-id/data/${rel}"
  echo "  apply $api" >&2
  hub apply "$api" -f "$f" -encrypt >/dev/null
done < <(find "${BACKUP_HOME}/data" -type f ! -name '.DS_Store' | sort)

if [[ -n "${TUNNEL_TOKEN:-}" ]]; then
  hub apply live/cloudflare/token.txt -f <(printf '%s\n' "$TUNNEL_TOKEN") -encrypt >/dev/null
fi

echo "Done — pocket/homelab/*, secrets/homelab/pocket-id.env, live/pocket-id/* (db, data/**, encryption.key), live/cloudflare/token.txt"

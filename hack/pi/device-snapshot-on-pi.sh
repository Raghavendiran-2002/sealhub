#!/usr/bin/env bash
# Run ON the Pi: quiesce podman, snapshot hub + Pocket ID data to OUT_DIR, restart stacks.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/podman-stacks.sh
source "$SCRIPT_DIR/lib/podman-stacks.sh" 2>/dev/null || source /tmp/sealhub-device-backup/lib/podman-stacks.sh

OUT_DIR="${1:?usage: device-snapshot-on-pi.sh /path/to/out-dir}"
SEALHUB_REPO="${SEALHUB_REPO:-/var/lib/sealhub/repo}"
POCKET_ID_HOME="${POCKET_ID_HOME:-$HOME/pocket-id}"
POCKET_BACKUP_STOP="${POCKET_BACKUP_STOP:-1}"

mkdir -p "$OUT_DIR"

cleanup() {
  start_all_stacks
}
trap cleanup EXIT

if [[ "$POCKET_BACKUP_STOP" == "1" ]]; then
  stop_pocket_id
fi

if [[ -n "${SEALHUB_TOKEN:-}" ]] && command -v hub >/dev/null && [[ -d "${POCKET_ID_HOME}/data" ]]; then
  if curl -sf http://127.0.0.1:8080/healthz >/dev/null 2>&1; then
    echo "hub pocket backup (documents in sealhub-data)..." >&2
    hub pocket backup -dir "$POCKET_ID_HOME" -no-stop 2>/dev/null || true
  fi
fi

stop_extra_containers
stop_hubd

echo "archiving $SEALHUB_REPO ..." >&2
tar -czf "$OUT_DIR/sealhub-repo.tar.gz" -C "$(dirname "$SEALHUB_REPO")" "$(basename "$SEALHUB_REPO")"

if [[ -d "${POCKET_ID_HOME}/data" ]]; then
  echo "archiving ${POCKET_ID_HOME} ..." >&2
  tar -czf "$OUT_DIR/pocket-id-home.tar.gz" -C "$(dirname "$POCKET_ID_HOME")" \
    "$(basename "$POCKET_ID_HOME")"
fi

if [[ -f /etc/sealhub/config.yaml ]]; then
  mkdir -p "$OUT_DIR/etc-sealhub"
  cp -a /etc/sealhub/config.yaml "$OUT_DIR/etc-sealhub/"
fi

python3 - "$OUT_DIR" <<'PY'
import json, os, socket, subprocess, datetime, sys
out = sys.argv[1]
meta = {
    "created_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "hostname": socket.gethostname(),
    "hubd_image": subprocess.getoutput("podman inspect sealhub-hubd --format '{{.ImageName}}' 2>/dev/null") or "",
}
with open(os.path.join(out, "metadata.json"), "w") as f:
    json.dump(meta, f, indent=2)
    f.write("\n")
PY

echo "snapshot written to $OUT_DIR" >&2

#!/usr/bin/env bash
# Keep at most RETENTION timestamped dirs under sealhub-data device-live/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SEALHUB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEFAULT_DATA="${SEALHUB_DATA_ROOT:-$SEALHUB_ROOT/../sealhub-data}"
BACKUP_ROOT="${1:-$DEFAULT_DATA/device-live}"
RETENTION="${DEVICE_BACKUP_RETENTION:-3}"

[[ -d "$BACKUP_ROOT" ]] || exit 0

mapfile -t dirs < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name '20*' | sort -r)
keep=()
prune=()
for i in "${!dirs[@]}"; do
  if (( i < RETENTION )); then
    keep+=("${dirs[$i]}")
  else
    prune+=("${dirs[$i]}")
  fi
done

for d in "${prune[@]}"; do
  echo "prune $d" >&2
  rm -rf "$d"
done

python3 - "$BACKUP_ROOT" "$RETENTION" "${keep[@]}" <<'PY'
import json, os, sys
root, retention = sys.argv[1], int(sys.argv[2])
ids = [os.path.basename(p) for p in sys.argv[3:]]
manifest = {
    "retention": retention,
    "snapshots": [{"id": i, "path": f"{root}/{i}"} for i in sorted(ids, reverse=True)],
}
path = os.path.join(root, "manifest.json")
os.makedirs(root, exist_ok=True)
with open(path, "w") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")
PY

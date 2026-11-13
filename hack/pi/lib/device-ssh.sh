# Shared SSH helpers for device backup/restore (Tailscale SSH).
# shellcheck shell=bash
DEVICE_SSH_CONTROL_PATH="${DEVICE_SSH_CONTROL_PATH:-${TMPDIR:-/tmp}/sealhub-ssh-%C}"

device_ssh_die() {
  echo "SSH to ${DEVICE_SSH_USER}@${DEVICE_SSH_HOST} failed (BatchMode). Use Tailscale, SSH keys, or LIVE_PASS." >&2
  exit 1
}

device_ssh_master_opts() {
  DEVICE_SSH_OPTS+=(
    -o ControlMaster=auto
    -o "ControlPath=${DEVICE_SSH_CONTROL_PATH}"
    -o ControlPersist=300
  )
}

device_ssh_close_master() {
  ssh "${DEVICE_SSH_OPTS[@]}" -o BatchMode=yes -O exit \
    "${DEVICE_SSH_USER}@${DEVICE_SSH_HOST}" 2>/dev/null || true
  if [[ -n "${DEVICE_SSH_FALLBACK_HOST:-}" ]]; then
    ssh "${DEVICE_SSH_OPTS[@]}" -o BatchMode=yes -O exit \
      "${DEVICE_SSH_USER}@${DEVICE_SSH_FALLBACK_HOST}" 2>/dev/null || true
  fi
}

device_ssh_batch() {
  ssh "${DEVICE_SSH_OPTS[@]}" -o BatchMode=yes \
    "${DEVICE_SSH_USER}@${DEVICE_SSH_HOST}" "$@"
}

_device_ssh_try() {
  local host="$1"
  shift
  DEVICE_SSH_HOST="$host"
  device_ssh_batch "$@"
}

_device_scp_try() {
  local host="$1" mode="$2" rpath="$3" lpath="$4"
  DEVICE_SSH_HOST="$host"
  if [[ "$mode" == from ]]; then
    scp "${DEVICE_SSH_OPTS[@]}" -o BatchMode=yes \
      "${DEVICE_SSH_USER}@${DEVICE_SSH_HOST}:${rpath}" "$lpath"
  else
    scp "${DEVICE_SSH_OPTS[@]}" -o BatchMode=yes \
      "$lpath" "${DEVICE_SSH_USER}@${DEVICE_SSH_HOST}:${rpath}"
  fi
}

_device_ssh_hosts() {
  local -n _out=$1
  _out=("$DEVICE_SSH_PRIMARY_HOST")
  if [[ -n "${DEVICE_SSH_FALLBACK_HOST:-}" && "${DEVICE_SSH_FALLBACK_HOST}" != "${DEVICE_SSH_PRIMARY_HOST}" ]]; then
    _out+=("$DEVICE_SSH_FALLBACK_HOST")
  fi
}

device_ssh_remote() {
  local hosts h attempt cmd=("$@")
  _device_ssh_hosts hosts
  for attempt in 1 2 3 4 5 6; do
    for h in "${hosts[@]}"; do
      if _device_ssh_try "$h" "${cmd[@]}" 2>/dev/null; then
        return 0
      fi
    done
    sleep "$(( attempt * 4 ))"
  done
  [[ -n "${LIVE_PASS:-}" ]] || device_ssh_die
  command -v sshpass >/dev/null || { echo "sshpass required" >&2; exit 1; }
  sshpass -p "$LIVE_PASS" ssh "${DEVICE_SSH_OPTS[@]}" "${DEVICE_SSH_USER}@${DEVICE_SSH_HOST}" "$@"
}

device_ssh_scp_from() {
  local remote_path="$1" local_path="$2" hosts h attempt
  _device_ssh_hosts hosts
  for attempt in 1 2 3 4 5 6; do
    for h in "${hosts[@]}"; do
      if _device_scp_try "$h" from "$remote_path" "$local_path" 2>/dev/null; then
        return 0
      fi
    done
    sleep "$(( attempt * 4 ))"
  done
  [[ -n "${LIVE_PASS:-}" ]] || device_ssh_die
  sshpass -p "$LIVE_PASS" scp "${DEVICE_SSH_OPTS[@]}" \
    "${DEVICE_SSH_USER}@${DEVICE_SSH_HOST}:${remote_path}" "$local_path"
}

device_ssh_scp_to() {
  local local_path="$1" remote_path="$2" hosts h attempt
  _device_ssh_hosts hosts
  for attempt in 1 2 3 4 5 6; do
    for h in "${hosts[@]}"; do
      if _device_scp_try "$h" to "$remote_path" "$local_path" 2>/dev/null; then
        return 0
      fi
    done
    sleep "$(( attempt * 4 ))"
  done
  [[ -n "${LIVE_PASS:-}" ]] || device_ssh_die
  sshpass -p "$LIVE_PASS" scp "${DEVICE_SSH_OPTS[@]}" \
    "$local_path" "${DEVICE_SSH_USER}@${DEVICE_SSH_HOST}:${remote_path}"
}

device_ssh_push_file() {
  local src="$1" dest="$2"
  device_ssh_remote "mkdir -p '$(dirname "$dest")'"
  device_ssh_scp_to "$src" "$dest"
}

device_ssh_pull_archive() {
  local remote_tgz="$1" local_dir="$2"
  mkdir -p "$local_dir"
  local local_tgz
  local_tgz="$(mktemp "${TMPDIR:-/tmp}/sealhub-pull.XXXXXX.tar.gz")"
  device_ssh_scp_from "$remote_tgz" "$local_tgz"
  tar -xzf "$local_tgz" -C "$local_dir"
  rm -f "$local_tgz"
  device_ssh_remote "rm -f '$remote_tgz'"
}

device_ssh_push_dir() {
  local local_dir="$1" remote_dir="$2"
  local tag remote_tgz local_tgz
  tag="$(date +%s)-$$"
  remote_tgz="/tmp/sealhub-device-${tag}.tar.gz"
  local_tgz="$(mktemp "${TMPDIR:-/tmp}/sealhub-push.XXXXXX.tar.gz")"
  tar -czf "$local_tgz" -C "$local_dir" .
  device_ssh_remote "mkdir -p '$remote_dir'"
  device_ssh_scp_to "$local_tgz" "$remote_tgz"
  rm -f "$local_tgz"
  device_ssh_remote "rm -rf '$remote_dir' && mkdir -p '$remote_dir' && tar -xzf '$remote_tgz' -C '$remote_dir' && rm -f '$remote_tgz'"
}

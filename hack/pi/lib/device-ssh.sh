# Shared SSH helpers for device backup/restore (Tailscale SSH).
# Prefer one archive file + scp (remote globs and tar|ssh streams are flaky on tailscale ssh).
# shellcheck shell=bash
device_ssh_die() {
  echo "SSH to ${DEVICE_SSH_USER}@${DEVICE_SSH_HOST} failed (BatchMode). Use Tailscale, SSH keys, or LIVE_PASS." >&2
  exit 1
}

device_ssh_batch() {
  ssh "${DEVICE_SSH_OPTS[@]}" -o BatchMode=yes "${DEVICE_SSH_USER}@${DEVICE_SSH_HOST}" "$@"
}

device_ssh_remote() {
  if device_ssh_batch "$@" 2>/dev/null; then
    return 0
  fi
  [[ -n "${LIVE_PASS:-}" ]] || device_ssh_die
  command -v sshpass >/dev/null || { echo "sshpass required" >&2; exit 1; }
  sshpass -p "$LIVE_PASS" ssh "${DEVICE_SSH_OPTS[@]}" "${DEVICE_SSH_USER}@${DEVICE_SSH_HOST}" "$@"
}

device_ssh_scp_from() {
  local remote_path="$1" local_path="$2"
  if scp "${DEVICE_SSH_OPTS[@]}" -o BatchMode=yes \
    "${DEVICE_SSH_USER}@${DEVICE_SSH_HOST}:${remote_path}" "$local_path" 2>/dev/null; then
    return 0
  fi
  [[ -n "${LIVE_PASS:-}" ]] || device_ssh_die
  sshpass -p "$LIVE_PASS" scp "${DEVICE_SSH_OPTS[@]}" \
    "${DEVICE_SSH_USER}@${DEVICE_SSH_HOST}:${remote_path}" "$local_path"
}

device_ssh_scp_to() {
  local local_path="$1" remote_path="$2"
  if scp "${DEVICE_SSH_OPTS[@]}" -o BatchMode=yes \
    "$local_path" "${DEVICE_SSH_USER}@${DEVICE_SSH_HOST}:${remote_path}" 2>/dev/null; then
    return 0
  fi
  [[ -n "${LIVE_PASS:-}" ]] || device_ssh_die
  sshpass -p "$LIVE_PASS" scp "${DEVICE_SSH_OPTS[@]}" \
    "$local_path" "${DEVICE_SSH_USER}@${DEVICE_SSH_HOST}:${remote_path}"
}

device_ssh_push_file() {
  local src="$1" dest="$2"
  device_ssh_remote "mkdir -p '$(dirname "$dest")'"
  device_ssh_scp_to "$src" "$dest"
}

device_ssh_pull_dir() {
  local remote_dir="$1" local_dir="$2"
  local tag
  tag="$(date +%s)-$$"
  local remote_tgz="/tmp/sealhub-device-${tag}.tar.gz"
  mkdir -p "$local_dir"
  device_ssh_remote "tar -C '$remote_dir' -czf '$remote_tgz' ."
  local local_tgz
  local_tgz="$(mktemp "${TMPDIR:-/tmp}/sealhub-pull.XXXXXX.tar.gz")"
  device_ssh_scp_from "$remote_tgz" "$local_tgz"
  tar -xzf "$local_tgz" -C "$local_dir"
  rm -f "$local_tgz"
  device_ssh_remote "rm -f '$remote_tgz'"
}

device_ssh_push_dir() {
  local local_dir="$1" remote_dir="$2"
  local tag
  tag="$(date +%s)-$$"
  local remote_tgz="/tmp/sealhub-device-${tag}.tar.gz"
  local local_tgz
  local_tgz="$(mktemp "${TMPDIR:-/tmp}/sealhub-push.XXXXXX.tar.gz")"
  tar -czf "$local_tgz" -C "$local_dir" .
  device_ssh_remote "mkdir -p '$remote_dir'"
  device_ssh_scp_to "$local_tgz" "$remote_tgz"
  rm -f "$local_tgz"
  device_ssh_remote "rm -rf '$remote_dir' && mkdir -p '$remote_dir' && tar -xzf '$remote_tgz' -C '$remote_dir' && rm -f '$remote_tgz'"
}

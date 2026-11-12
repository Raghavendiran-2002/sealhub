# Shared SSH helpers for device backup/restore (Tailscale SSH; avoid scp/globs).
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

# Push a single file over SSH (no scp — unreliable with Tailscale SSH).
device_ssh_push_file() {
  local src="$1" dest="$2"
  device_ssh_remote "mkdir -p '$(dirname "$dest")'"
  if cat "$src" | device_ssh_batch "cat > '$dest'" 2>/dev/null; then
    return 0
  fi
  [[ -n "${LIVE_PASS:-}" ]] || device_ssh_die
  cat "$src" | sshpass -p "$LIVE_PASS" ssh "${DEVICE_SSH_OPTS[@]}" "${DEVICE_SSH_USER}@${DEVICE_SSH_HOST}" "cat > '$dest'"
}

# Pull a remote directory as a tar stream.
device_ssh_pull_dir() {
  local remote_dir="$1" local_dir="$2"
  mkdir -p "$local_dir"
  if device_ssh_batch "tar -C '$remote_dir' -cf - ." | tar -C "$local_dir" -xf -; then
    return 0
  fi
  [[ -n "${LIVE_PASS:-}" ]] || device_ssh_die
  sshpass -p "$LIVE_PASS" ssh "${DEVICE_SSH_OPTS[@]}" "${DEVICE_SSH_USER}@${DEVICE_SSH_HOST}" \
    "tar -C '$remote_dir' -cf - ." | tar -C "$local_dir" -xf -
}

# Push a local directory as a tar stream.
device_ssh_push_dir() {
  local local_dir="$1" remote_dir="$2"
  device_ssh_remote "rm -rf '$remote_dir' && mkdir -p '$remote_dir'"
  if tar -C "$local_dir" -cf - . | device_ssh_batch "tar -C '$remote_dir' -xf -"; then
    return 0
  fi
  [[ -n "${LIVE_PASS:-}" ]] || device_ssh_die
  tar -C "$local_dir" -cf - . | sshpass -p "$LIVE_PASS" ssh "${DEVICE_SSH_OPTS[@]}" \
    "${DEVICE_SSH_USER}@${DEVICE_SSH_HOST}" "tar -C '$remote_dir' -xf -"
}

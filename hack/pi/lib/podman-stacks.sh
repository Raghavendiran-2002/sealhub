# shellcheck shell=bash
# Stop/start Pi podman stacks (pocket-id compose + sealhub-hubd container).
[[ -n "${_PODMAN_STACKS_LIB:-}" ]] && return 0
_PODMAN_STACKS_LIB=1

POCKET_ID_HOME="${POCKET_ID_HOME:-$HOME/pocket-id}"
HUBD_CONTAINER="${HUBD_CONTAINER:-sealhub-hubd}"
EXTRA_CONTAINERS="${EXTRA_CONTAINERS:-cloudflared starry-cloud}"

_was_running() {
  podman inspect "$1" --format '{{.State.Running}}' 2>/dev/null | grep -qi true
}

stop_pocket_id() {
  if _was_running pocket-id; then
    echo "stopping pocket-id..." >&2
    if [[ -f "${POCKET_ID_HOME}/docker-compose.yaml" ]] || [[ -f "${POCKET_ID_HOME}/docker-compose.yml" ]]; then
      (cd "$POCKET_ID_HOME" && podman compose stop pocket-id) 2>/dev/null \
        || (cd "$POCKET_ID_HOME" && podman-compose stop pocket-id) 2>/dev/null \
        || podman stop pocket-id
    else
      podman stop pocket-id
    fi
    sleep 2
    export POCKET_ID_WAS_RUNNING=true
  fi
}

start_pocket_id() {
  if [[ "${POCKET_ID_WAS_RUNNING:-}" == "true" ]] || [[ "${FORCE_START_POCKET:-}" == "1" ]]; then
    echo "starting pocket-id stack..." >&2
    if [[ -f "${POCKET_ID_HOME}/docker-compose.yaml" ]] || [[ -f "${POCKET_ID_HOME}/docker-compose.yml" ]]; then
      (cd "$POCKET_ID_HOME" && podman compose up -d) 2>/dev/null \
        || (cd "$POCKET_ID_HOME" && podman-compose up -d) 2>/dev/null \
        || podman start pocket-id 2>/dev/null || true
    else
      podman start pocket-id 2>/dev/null || true
    fi
  fi
}

stop_hubd() {
  if _was_running "$HUBD_CONTAINER"; then
    echo "stopping $HUBD_CONTAINER..." >&2
    podman stop "$HUBD_CONTAINER"
    export HUBD_WAS_RUNNING=true
  fi
}

start_hubd() {
  if [[ "${HUBD_WAS_RUNNING:-}" == "true" ]] || [[ "${FORCE_START_HUBD:-}" == "1" ]]; then
    echo "starting $HUBD_CONTAINER..." >&2
    podman start "$HUBD_CONTAINER" 2>/dev/null || true
  fi
}

stop_extra_containers() {
  : >"${RUN_DIR:=/tmp}/.sealhub-extra-running" 2>/dev/null || RUN_DIR=/tmp
  for c in $EXTRA_CONTAINERS; do
    if _was_running "$c"; then
      echo "stopping $c..." >&2
      podman stop "$c" || true
      echo "$c" >>"$RUN_DIR/.sealhub-extra-running"
    fi
  done
}

start_extra_containers() {
  [[ -f "${RUN_DIR:-/tmp}/.sealhub-extra-running" ]] || return 0
  while read -r c; do
    [[ -n "$c" ]] && podman start "$c" 2>/dev/null || true
  done <"$RUN_DIR/.sealhub-extra-running"
}

stop_all_stacks() {
  stop_pocket_id
  stop_extra_containers
  stop_hubd
}

start_all_stacks() {
  start_hubd
  sleep 2
  start_extra_containers
  start_pocket_id
}

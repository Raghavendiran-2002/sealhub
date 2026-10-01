#!/usr/bin/env bash
# Deploy RootOS dashboard on live Pi using GHCR image (Podman compose).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIVE_HOST="${LIVE_HOST:-100.114.97.68}"
LIVE_USER="${LIVE_USER:-pi}"
POCKET_DIR="${POCKET_DIR:-/home/pi/pocket-id}"
STANDALONE_DIR="${ROOTOS_STANDALONE_DIR:-/home/pi/starry-cloud}"
ROOTOS_IMAGE="${ROOTOS_IMAGE:-ghcr.io/raghavendiran-2002/rootos:latest}"

SSH=(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=30 "${LIVE_USER}@${LIVE_HOST}")
SCP=(scp -o BatchMode=yes -o StrictHostKeyChecking=accept-new)

echo "==> Deploy RootOS dashboard to ${LIVE_USER}@${LIVE_HOST}" >&2
"${SSH[@]}" "podman pull ${ROOTOS_IMAGE}"

if "${SSH[@]}" "test -d ${POCKET_DIR}"; then
  echo "==> Pocket ID stack at ${POCKET_DIR}" >&2
  "${SSH[@]}" "mkdir -p ${POCKET_DIR}/starry"
  "${SCP[@]}" "$ROOT/hack/pi/rootos/config.yml" "${LIVE_USER}@${LIVE_HOST}:${POCKET_DIR}/starry/config.yml"
  if ! "${SSH[@]}" "test -f ${POCKET_DIR}/starry/auth.yml"; then
    if "${SSH[@]}" "test -f ${STANDALONE_DIR}/auth.yml"; then
      "${SCP[@]}" "${LIVE_USER}@${LIVE_HOST}:${STANDALONE_DIR}/auth.yml" "/tmp/rootos-auth.yml"
      "${SCP[@]}" "/tmp/rootos-auth.yml" "${LIVE_USER}@${LIVE_HOST}:${POCKET_DIR}/starry/auth.yml"
      rm -f /tmp/rootos-auth.yml
    else
      echo "Missing auth.yml (expected ${POCKET_DIR}/starry/auth.yml or ${STANDALONE_DIR}/auth.yml)" >&2
      exit 1
    fi
  fi
  "${SCP[@]}" "$ROOT/hack/pi/podman-compose/pocket-id/docker-compose.yaml" \
    "${LIVE_USER}@${LIVE_HOST}:${POCKET_DIR}/docker-compose.yaml"
  "${SSH[@]}" "cd ${POCKET_DIR} && export ROOTOS_IMAGE='${ROOTOS_IMAGE}' METRICS_TOKEN='${METRICS_TOKEN:-}' && \
    podman compose up -d --force-recreate rootos"
else
  echo "==> Standalone stack at ${STANDALONE_DIR}" >&2
  "${SSH[@]}" "mkdir -p ${STANDALONE_DIR}"
  "${SCP[@]}" "$ROOT/hack/pi/rootos/config.yml" "$ROOT/hack/pi/rootos/docker-compose.yml" \
    "${LIVE_USER}@${LIVE_HOST}:${STANDALONE_DIR}/"
  if ! "${SSH[@]}" "test -f ${STANDALONE_DIR}/auth.yml"; then
    echo "Missing ${STANDALONE_DIR}/auth.yml" >&2
    exit 1
  fi
  "${SSH[@]}" "cd ${STANDALONE_DIR} && export ROOTOS_IMAGE='${ROOTOS_IMAGE}' METRICS_TOKEN='${METRICS_TOKEN:-}' && \
    podman compose up -d --force-recreate"
fi

"${SSH[@]}" "curl -sf http://127.0.0.1:5000/health"
echo "RootOS dashboard health OK on ${LIVE_HOST}:5000" >&2

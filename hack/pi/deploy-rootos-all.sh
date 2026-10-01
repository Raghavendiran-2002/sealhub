#!/usr/bin/env bash
# Pull the same RootOS GHCR image on both Pis: agent (100.66.190.37) + dashboard (100.114.97.68).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOTOS_IMAGE="${ROOTOS_IMAGE:-ghcr.io/raghavendiran-2002/rootos:latest}"
REMOTE_HOST="${REMOTE_HOST:-100.66.190.37}"
LIVE_HOST="${LIVE_HOST:-100.114.97.68}"

[[ -n "${METRICS_TOKEN:-}" ]] || {
  echo "Set METRICS_TOKEN (agent METRICS_TOKEN + dashboard METRICS_REMOTE_TOKEN)" >&2
  exit 1
}

export ROOTOS_IMAGE METRICS_TOKEN REMOTE_HOST LIVE_HOST

echo "==> [1/2] Metrics agent on ${REMOTE_HOST}" >&2
"$ROOT/hack/pi/deploy-rootos-agent-ssh.sh"

echo "==> [2/2] Dashboard on ${LIVE_HOST}" >&2
"$ROOT/hack/pi/deploy-rootos-live-ssh.sh"

echo "==> End-to-end: dashboard fetches remote metrics" >&2
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "pi@${LIVE_HOST}" \
  "curl -sf -H \"Authorization: Bearer ${METRICS_TOKEN}\" http://${REMOTE_HOST}:9090/api/system-stats | head -c 120"
echo ""
echo "Done. Open the dashboard and confirm two System sections." >&2

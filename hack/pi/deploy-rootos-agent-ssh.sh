#!/usr/bin/env bash
# Install/update RootOS metrics agent on a remote Pi via systemd + Podman.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REMOTE_HOST="${REMOTE_HOST:-100.66.190.37}"
REMOTE_USER="${REMOTE_USER:-pi}"
ROOTOS_IMAGE="${ROOTOS_IMAGE:-ghcr.io/raghavendiran-2002/rootos:latest}"

[[ -n "${METRICS_TOKEN:-}" ]] || {
  echo "Set METRICS_TOKEN (shared with dashboard METRICS_REMOTE_TOKEN)" >&2
  exit 1
}

SSH=(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=30 "${REMOTE_USER}@${REMOTE_HOST}")
SCP=(scp -o BatchMode=yes -o StrictHostKeyChecking=accept-new)

echo "==> Deploy RootOS metrics agent to ${REMOTE_USER}@${REMOTE_HOST}" >&2

"${SSH[@]}" "sudo mkdir -p /etc/rootos && sudo chown ${REMOTE_USER}:${REMOTE_USER} /etc/rootos"

ENV_FILE=$(mktemp)
cat >"$ENV_FILE" <<EOF
ROOTOS_IMAGE=${ROOTOS_IMAGE}
ROOTOS_AGENT_LISTEN=0.0.0.0:9090
METRICS_TOKEN=${METRICS_TOKEN}
EOF
"${SCP[@]}" "$ENV_FILE" "${REMOTE_USER}@${REMOTE_HOST}:/tmp/rootos-agent.env"
rm -f "$ENV_FILE"
"${SSH[@]}" "mv /tmp/rootos-agent.env /etc/rootos/agent.env && chmod 600 /etc/rootos/agent.env"

"${SCP[@]}" "$ROOT/hack/pi/rootos-metrics-agent/rootos-metrics-agent.service" \
  "${REMOTE_USER}@${REMOTE_HOST}:/tmp/rootos-metrics-agent.service"
"${SSH[@]}" "sudo mv /tmp/rootos-metrics-agent.service /etc/systemd/system/rootos-metrics-agent.service && sudo systemctl daemon-reload"

echo "==> Pull ${ROOTOS_IMAGE} and start agent" >&2
"${SSH[@]}" "podman pull ${ROOTOS_IMAGE} && sudo systemctl enable --now rootos-metrics-agent.service"

sleep 3
"${SSH[@]}" "curl -sf http://127.0.0.1:9090/health"
"${SSH[@]}" "curl -sf -H \"Authorization: Bearer ${METRICS_TOKEN}\" http://127.0.0.1:9090/api/system-stats | head -c 200"
echo ""
echo "RootOS metrics agent running on ${REMOTE_HOST}:9090" >&2

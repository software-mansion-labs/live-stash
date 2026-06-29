#!/usr/bin/env bash
# Set LIVE_STASH_TTL + cleanup intervals on every app VM and restart.
# Static copy for manual installs — Ansible deploys a templated version to /opt/k6/.
#
# Usage:
#   APP_HOSTS="10.10.0.3 10.10.0.4" ./configure_app_perf.sh --ttl 300 --cleanup 30
set -euo pipefail

APP_HOSTS="${APP_HOSTS:-10.10.0.3 10.10.0.4}"
SSH_PORT="${SSH_PORT:-2222}"
SSH_USER="${SSH_USER:-root}"
SSH_OPTS="${SSH_OPTS:--o BatchMode=yes -o StrictHostKeyChecking=accept-new}"

TTL=60
CLEANUP_S=30

usage() {
  sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ttl) TTL="$2"; shift 2 ;;
    --cleanup) CLEANUP_S="$2"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "unknown option: $1" >&2; usage 1 ;;
  esac
done

CLEANUP_MS=$((CLEANUP_S * 1000))

echo "configuring app cluster: LIVE_STASH_TTL=${TTL}s cleanup=${CLEANUP_S}s (${CLEANUP_MS}ms)"

for host in $APP_HOSTS; do
  echo "  → ${host}"
  ssh -p "$SSH_PORT" $SSH_OPTS "${SSH_USER}@${host}" \
    "TTL=${TTL} CLEANUP_MS=${CLEANUP_MS} bash -s" <<'REMOTE'
set -euo pipefail
ENV=/etc/livestash/app.env
touch "$ENV"

set_kv() {
  local key="$1" val="$2"
  if grep -q "^${key}=" "$ENV"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$ENV"
  else
    echo "${key}=${val}" >>"$ENV"
  fi
}

set_kv LIVE_STASH_TTL "$TTL"
set_kv LIVE_STASH_ETS_CLEANUP_INTERVAL_MS "$CLEANUP_MS"
set_kv LIVE_STASH_MNESIA_CLEANUP_INTERVAL_MS "$CLEANUP_MS"

systemctl restart livestash-app
REMOTE
done

echo "waiting for app nodes..."
sleep 5
echo "done"

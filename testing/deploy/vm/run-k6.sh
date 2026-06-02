#!/usr/bin/env bash
# Run the load test natively on the load VM (k6 installed on host).
# Usage:
#   OBS_VM=10.0.0.5 ./run-k6.sh -e BASE_PATH=/performance/livestash_redis
# By default k6 hits the nginx load balancer on the obs VM, which fans out to
# the app cluster (so reconnects exercise cross-node recovery). Override HOST to
# target a single app node directly.
# Extra args (-e KEY=VAL ...) pass straight through to `k6 run`.
set -euo pipefail

# fd ceiling for this shell (the sysctl/limits files raise the hard cap).
ulimit -n 1048576 || true

OBS_VM="${OBS_VM:-OBS_VM}"
HOST="${HOST:-${OBS_VM}:80}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST="$SCRIPT_DIR/../../k6/load_test.js"

export HOST
export K6_PROMETHEUS_RW_SERVER_URL="${K6_PROMETHEUS_RW_SERVER_URL:-http://${OBS_VM}:9090/api/v1/write}"
export K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM=true

exec k6 run --out=experimental-prometheus-rw "$TEST" "$@"

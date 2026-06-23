#!/usr/bin/env bash
# Run the load test natively on the load VM (k6 installed on host).
# Usage:
#   ./run-k6.sh -e BASE_PATH=/performance/livestash_redis
# nginx (the LB) runs on THIS k6 VM. Prefer the VM's own IP over 127.0.0.1 for
# high VU counts — loopback exhausts its ~64k ephemeral-port pool around 15–20k
# long-lived WebSockets. Override HOST to target a single app node directly,
# e.g. HOST=10.10.0.3:4000.
# OBS_VM is the Prometheus/Grafana VM that receives k6 remote-write metrics.
# Extra args (-e KEY=VAL ...) pass straight through to `k6 run`.
set -euo pipefail

# fd ceiling for this shell (the sysctl/limits files raise the hard cap).
ulimit -n 1048576 || true

OBS_VM="${OBS_VM:-10.10.0.2}"
HOST="${HOST:-127.0.0.1:80}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST="$SCRIPT_DIR/../../k6/load_test.js"

export HOST
export K6_PROMETHEUS_RW_SERVER_URL="${K6_PROMETHEUS_RW_SERVER_URL:-http://${OBS_VM}:9090/api/v1/write}"
export K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM=true
export K6_PROMETHEUS_RW_PUSH_INTERVAL="${K6_PROMETHEUS_RW_PUSH_INTERVAL:-10s}"

exec k6 run --out=experimental-prometheus-rw "$TEST" "$@"

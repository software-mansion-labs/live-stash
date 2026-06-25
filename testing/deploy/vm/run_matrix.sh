#!/usr/bin/env bash
# Run load-test matrix cells on the load VM and append results to runs.csv.
#
# Configures app TTL/cleanup via configure_app_perf.sh before each block,
# runs k6 with matching TTL + duration, logs timestamps to runs.csv.
#
# Usage (on load VM):
#   ./run_matrix.sh --ttl 60 --vus 1000 --adapter all
#   ./run_matrix.sh --ttl 60 --matrix
#   ./run_matrix.sh --matrix-full
#
# Copy runs.csv back for charts:
#   scp -P 2222 root@LOAD_VM:/opt/k6/runs.csv testing/observability/charts/
#   cd testing/observability/charts && ./generate_charts.sh --group ttl60s-vus1000
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K6="${K6:-${SCRIPT_DIR}/run-k6.sh}"
APP_CONFIG="${APP_CONFIG:-${SCRIPT_DIR}/configure_app_perf.sh}"
RUN_LOG="${RUN_LOG:-/opt/k6/runs.csv}"

SIZE_KB="${SIZE_KB:-5}"
CLEANUP_S="${CLEANUP_S:-30}"
PAUSE_SEC="${PAUSE_SEC:-30}"
RECONNECT_PCT="${RECONNECT_PCT:-50}"
CONFIGURE_APP="${CONFIGURE_APP:-1}"

CSV_HEADER="run_id,group,label,adapter,base_path,ttl_s,vus,cleanup_s,size_kb,tags,start,end,notes"

ADAPTER_ORDER=(baseline ets redis mnesia)
DEFAULT_TTLS=(60 300 900)
DEFAULT_VUSS=(1000 10000 20000 30000)

adapter_label() {
  case "$1" in
    baseline) echo Baseline ;;
    ets) echo ETS ;;
    redis) echo Redis ;;
    mnesia) echo Mnesia ;;
    *) return 1 ;;
  esac
}

adapter_path() {
  case "$1" in
    baseline) echo /performance/baseline ;;
    ets) echo /performance/livestash_ets ;;
    redis) echo /performance/livestash_redis ;;
    mnesia) echo /performance/livestash_mnesia ;;
    *) return 1 ;;
  esac
}

adapter_tags() {
  case "$1" in
    redis) echo redis ;;
    *) echo "" ;;
  esac
}

TTL=""
VUS=""
ADAPTER=""
GROUP=""
MATRIX=0
MATRIX_FULL=0
DRY_RUN=0
NO_CONFIGURE=0

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

apply_app_config() {
  local ttl="$1" cleanup="$2"
  if [[ "$CONFIGURE_APP" != "1" || "$NO_CONFIGURE" -eq 1 ]]; then
    echo "skip app configure (LIVE_STASH_TTL=${ttl}s cleanup=${cleanup}s)"
    return 0
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "dry-run: $APP_CONFIG --ttl $ttl --cleanup $cleanup"
    return 0
  fi
  if [[ ! -x "$APP_CONFIG" ]]; then
    echo "error: missing $APP_CONFIG — deploy with ansible --tags load or set NO_CONFIGURE=1" >&2
    exit 1
  fi
  "$APP_CONFIG" --ttl "$ttl" --cleanup "$cleanup"
}

test_duration_for_ttl() {
  case "$1" in
    60) echo 180 ;;
    300) echo 600 ;;
    900) echo 1500 ;;
    *) echo 180 ;;
  esac
}

group_name() {
  local ttl="$1" vus="$2" cleanup="$3"
  local g="ttl${ttl}s-vus${vus}"
  if [[ "$cleanup" != "30" ]]; then
    g="${g}-cleanup${cleanup}s"
  fi
  printf '%s' "$g"
}

init_csv() {
  if [[ ! -f "$RUN_LOG" ]]; then
    mkdir -p "$(dirname "$RUN_LOG")"
    echo "$CSV_HEADER" >"$RUN_LOG"
  elif ! head -1 "$RUN_LOG" | grep -q '^run_id,'; then
    echo "error: $RUN_LOG exists but missing expected header" >&2
    exit 1
  fi
}

next_run_id() {
  local max
  max="$(awk -F, 'NR > 1 && $1 ~ /^[0-9]+$/ { if ($1 > m) m = $1 } END { print m + 0 }' "$RUN_LOG")"
  echo $((max + 1))
}

run_one() {
  local ttl="$1" vus="$2" adapter="$3" cleanup="$4"
  local label base_path tags
  label="$(adapter_label "$adapter")" || { echo "error: unknown adapter '$adapter'" >&2; return 1; }
  base_path="$(adapter_path "$adapter")"
  tags="$(adapter_tags "$adapter")"
  local group="${GROUP:-$(group_name "$ttl" "$vus" "$cleanup")}"
  local duration
  duration="$(test_duration_for_ttl "$ttl")"
  local run_id start end

  if [[ ! -x "$K6" ]]; then
    echo "error: k6 wrapper not found or not executable: $K6" >&2
    exit 1
  fi

  echo ""
  echo "==> run_id next | group=$group | $label | ttl=${ttl}s vus=$vus cleanup=${cleanup}s duration=${duration}s"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "dry-run: $K6 -e BASE_PATH=$base_path -e VUS=$vus -e TTL=$ttl -e SIZE_KB=$SIZE_KB -e TEST_DURATION_SEC=$duration -e RECONNECT_WITHIN_TTL_PCT=$RECONNECT_PCT"
    return 0
  fi

  init_csv
  run_id="$(next_run_id)"
  start="$(date -Iseconds)"

  "$K6" \
    -e "BASE_PATH=$base_path" \
    -e "VUS=$vus" \
    -e "TTL=$ttl" \
    -e "SIZE_KB=$SIZE_KB" \
    -e "TEST_DURATION_SEC=$duration" \
    -e "RECONNECT_WITHIN_TTL_PCT=$RECONNECT_PCT"

  end="$(date -Iseconds)"

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,\n' \
    "$run_id" "$group" "$label" "$adapter" "$base_path" \
    "$ttl" "$vus" "$cleanup" "$SIZE_KB" "$tags" "$start" "$end" \
    >>"$RUN_LOG"

  echo "logged run_id=$run_id → $RUN_LOG"
}

adapters_for() {
  local pick="$1"
  if [[ "$pick" == all ]]; then
    printf '%s\n' "${ADAPTER_ORDER[@]}"
  else
    printf '%s\n' "$pick"
  fi
}

run_block() {
  local ttl="$1" vus="$2" adapter_pick="$3" cleanup="$4"
  apply_app_config "$ttl" "$cleanup"
  local a
  while IFS= read -r a; do
    run_one "$ttl" "$vus" "$a" "$cleanup"
    if [[ "$DRY_RUN" -eq 0 && "$PAUSE_SEC" -gt 0 ]]; then
      echo "pause ${PAUSE_SEC}s..."
      sleep "$PAUSE_SEC"
    fi
  done < <(adapters_for "$adapter_pick")
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --csv) RUN_LOG="$2"; shift 2 ;;
    --group) GROUP="$2"; shift 2 ;;
    --ttl) TTL="$2"; shift 2 ;;
    --vus) VUS="$2"; shift 2 ;;
    --cleanup) CLEANUP_S="$2"; shift 2 ;;
    --size-kb) SIZE_KB="$2"; shift 2 ;;
    --adapter) ADAPTER="$2"; shift 2 ;;
    --pause) PAUSE_SEC="$2"; shift 2 ;;
    --matrix) MATRIX=1; shift ;;
    --matrix-full) MATRIX_FULL=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --no-configure) NO_CONFIGURE=1; shift ;;
    -h|--help) usage 0 ;;
    *) echo "unknown option: $1" >&2; usage 1 ;;
  esac
done

if [[ "$MATRIX_FULL" -eq 1 ]]; then
  for ttl in "${DEFAULT_TTLS[@]}"; do
    echo ""
    echo "######## TTL=${ttl}s ########"
    for vus in "${DEFAULT_VUSS[@]}"; do
      run_block "$ttl" "$vus" all "$CLEANUP_S"
      # if [[ "$ttl" -eq 900 ]]; then
      #   echo "######## TTL=${ttl}s cleanup=450s (ETS + Mnesia only) ########"
      #   run_block "$ttl" "$vus" ets 450
      #   run_block "$ttl" "$vus" mnesia 450
      # fi
    done
  done
elif [[ "$MATRIX" -eq 1 ]]; then
  [[ -n "$TTL" ]] || { echo "error: --matrix requires --ttl" >&2; exit 1; }
  for vus in "${DEFAULT_VUSS[@]}"; do
    run_block "$TTL" "$vus" all "$CLEANUP_S"
  done
elif [[ -n "$ADAPTER" && -n "$TTL" && -n "$VUS" ]]; then
  if [[ "$ADAPTER" != all ]] && ! adapter_label "$ADAPTER" >/dev/null; then
    echo "error: unknown adapter '$ADAPTER' (baseline|ets|redis|mnesia|all)" >&2
    exit 1
  fi
  run_block "$TTL" "$VUS" "$ADAPTER" "$CLEANUP_S"
else
  echo "error: specify --ttl --vus --adapter, --matrix, or --matrix-full" >&2
  usage 1
fi

echo ""
echo "done. runs logged to $RUN_LOG"

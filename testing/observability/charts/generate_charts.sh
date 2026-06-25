#!/usr/bin/env bash
# Generate comparison charts from runs.csv + chart_config.yaml
#
# Usage:
#   ./generate_charts.sh
#   ./generate_charts.sh --group ttl60s-vus1000
#   ./generate_charts.sh -- --format svg --metrics beam_binary beam_ets
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ -d .venv ]]; then
  # shellcheck disable=SC1091
  source .venv/bin/activate
fi

CSV="${CSV:-runs.csv}"
CONFIG="${CONFIG:-chart_config.yaml}"
OUT="${OUT:-output}"

extra=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --csv) CSV="$2"; shift 2 ;;
    --config) CONFIG="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --) shift; extra+=("$@"); break ;;
    *) extra+=("$1"); shift ;;
  esac
done

exec python export_charts.py "$CSV" --config "$CONFIG" --out "$OUT" "${extra[@]}"

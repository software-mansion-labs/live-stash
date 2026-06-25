#!/usr/bin/env python3
"""
Download Prometheus metrics for multiple load test runs and generate
comparison charts for a technical article.

Each run corresponds to one adapter (e.g. Redis, ETS, Mnesia). Runs are
time-aligned so t=0 is the start of each run, enabling direct comparison on
the same x-axis.

Usage
-----
  ./generate_charts.sh
  python export_charts.py runs.csv
  python export_charts.py runs.csv --group ttl60s-vus1000 --out output/
  python export_charts.py runs.yaml          # legacy YAML format

runs.csv is produced by deploy/vm/run_matrix.sh on the load VM.
chart_config.yaml holds prometheus_url and step.

Requirements
------------
  pip install requests matplotlib pyyaml numpy
"""

import argparse
import csv
import sys
from pathlib import Path
from datetime import datetime, timezone

import requests
import numpy as np
import matplotlib
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import yaml

# ---------------------------------------------------------------------------
# Chart style - clean, publication-ready
# ---------------------------------------------------------------------------

ARTICLE_STYLE = {
    "figure.figsize": (10, 4.5),
    "figure.dpi": 150,
    "axes.spines.top": False,
    "axes.spines.right": False,
    "axes.grid": True,
    "axes.grid.axis": "y",
    "grid.alpha": 0.35,
    "grid.linestyle": "--",
    "lines.linewidth": 2,
    "font.family": "sans-serif",
    "font.size": 11,
    "axes.titlesize": 13,
    "axes.labelsize": 11,
    "legend.fontsize": 9,
    "legend.framealpha": 0.85,
    "xtick.direction": "out",
    "ytick.direction": "out",
}

# One color per adapter run (cycles if more than 8 runs)
ADAPTER_COLORS = [
    "#2196F3",  # blue
    "#E91E63",  # pink
    "#4CAF50",  # green
    "#FF9800",  # orange
    "#9C27B0",  # purple
    "#00BCD4",  # cyan
    "#795548",  # brown
    "#607D8B",  # blue-grey
]

# Quantile line styles: p50 solid, p95 dashed, p99 dotted
QUANTILE_STYLES = {
    "p50": ("-",  0.9),   # (linestyle, alpha)
    "p95": ("--", 0.75),
    "p99": (":",  0.65),
}

# Port I/O breakdown: HTTP/WS is always shown; node for clustered adapters;
# redis for the Redis adapter. Matches livestash_load_test Grafana panels.
PORT_IO_EXPRS = {
    "input": {
        "http_ws": (
            'sum(rate(testing_prom_ex_beam_stats_port_io_byte_count{type="input"}[1m]))'
            " - sum(rate(testing_port_io_dist_input[1m]))"
            " - sum(rate(redis_net_output_bytes_total[1m]))"
        ),
        "node": "sum(rate(testing_port_io_dist_input[1m]))",
        "redis": "sum(rate(redis_net_output_bytes_total[1m]))",
    },
    "output": {
        "http_ws": (
            'sum(rate(testing_prom_ex_beam_stats_port_io_byte_count{type="output"}[1m]))'
            " - sum(rate(testing_port_io_dist_output[1m]))"
            " - sum(rate(redis_net_input_bytes_total[1m]))"
        ),
        "node": "sum(rate(testing_port_io_dist_output[1m]))",
        "redis": "sum(rate(redis_net_input_bytes_total[1m]))",
    },
}

IO_COMPONENT_STYLE = {
    "http_ws": ("-", 0.9),
    "node": ("--", 0.85),
    "redis": (":", 0.85),
}

# ---------------------------------------------------------------------------
# Config loaders
# ---------------------------------------------------------------------------

def load_settings(config_path: Path | None) -> dict:
    if config_path is None or not config_path.exists():
        return {}
    with config_path.open() as f:
        data = yaml.safe_load(f) or {}
    return data if isinstance(data, dict) else {}


def load_runs_csv(csv_path: Path, group: str | None = None) -> list[dict]:
    """Load completed runs from runs.csv (rows without start/end are skipped)."""
    runs: list[dict] = []
    with csv_path.open(newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            start = (row.get("start") or "").strip()
            end = (row.get("end") or "").strip()
            if not start or not end:
                continue
            if group and (row.get("group") or "").strip() != group:
                continue

            tags_raw = (row.get("tags") or "").strip()
            tags = [t.strip() for t in tags_raw.split(",") if t.strip()]
            adapter = (row.get("adapter") or row.get("label") or "").strip()

            runs.append({
                "label": row["label"].strip(),
                "start": start,
                "end": end,
                "tags": tags,
                "prom_name": adapter.lower() if adapter else row["label"].strip().lower(),
            })
    return runs


def load_config(runs_path: Path, config_path: Path | None, group: str | None) -> tuple[dict, list[dict]]:
    if runs_path.suffix.lower() == ".csv":
        settings_path = config_path
        if settings_path is None:
            settings_path = runs_path.with_name("chart_config.yaml")
        settings = load_settings(settings_path)
        effective_group = group if group is not None else settings.get("default_group")
        runs = load_runs_csv(runs_path, group=effective_group)
        return settings, runs

    with runs_path.open() as f:
        cfg = yaml.safe_load(f) or {}
    return cfg, cfg.get("runs", [])


# ---------------------------------------------------------------------------
# Prometheus query helper
# ---------------------------------------------------------------------------

def query_range(prom_url: str, expr: str, start: float, end: float, step: str) -> list[dict]:
    """Return list of {metric: {labels}, values: [(t, v), ...]}."""
    resp = requests.get(
        f"{prom_url.rstrip('/')}/api/v1/query_range",
        params={"query": expr, "start": start, "end": end, "step": step},
        timeout=60,
    )
    resp.raise_for_status()
    data = resp.json()
    if data["status"] != "success":
        raise RuntimeError(f"Prometheus error for '{expr}': {data}")
    return data["data"]["result"]


def parse_iso(ts: str) -> float:
    """Parse ISO-8601 timestamp to POSIX seconds."""
    import re
    if ts.endswith("Z"):
        ts = ts[:-1] + "+00:00"
    # normalize +H:MM or -H:MM to +HH:MM so fromisoformat accepts it
    ts = re.sub(r"([+-])(\d):(\d{2})$", r"\g<1>0\2:\3", ts)
    return datetime.fromisoformat(ts).timestamp()


def series_to_xy(result_item: dict, t0: float) -> tuple[np.ndarray, np.ndarray]:
    """Convert a single Prometheus result series to (x_seconds, y_values)."""
    values = result_item["values"]
    xs = np.array([float(v[0]) - t0 for v in values])
    ys = np.array([float(v[1]) for v in values])
    return xs, ys


# ---------------------------------------------------------------------------
# Unit formatters
# ---------------------------------------------------------------------------

def bytes_formatter(ax):
    def _fmt(x, _):
        for unit, threshold in [("GB", 1e9), ("MB", 1e6), ("KB", 1e3)]:
            if x >= threshold:
                return f"{x/threshold:.1f} {unit}"
        return f"{x:.0f} B"
    ax.yaxis.set_major_formatter(mticker.FuncFormatter(_fmt))


def percent_formatter(ax):
    ax.yaxis.set_major_formatter(mticker.PercentFormatter(xmax=1.0))
    ax.set_ylim(bottom=0)


def ms_formatter(ax):
    ax.yaxis.set_major_formatter(mticker.FuncFormatter(lambda x, _: f"{x:.0f} ms"))


def seconds_formatter(ax):
    ax.yaxis.set_major_formatter(mticker.FuncFormatter(lambda x, _: f"{x*1000:.0f} ms"))


def bps_formatter(ax):
    def _fmt(x, _):
        for unit, threshold in [("GB/s", 1e9), ("MB/s", 1e6), ("KB/s", 1e3)]:
            if x >= threshold:
                return f"{x/threshold:.1f} {unit}"
        return f"{x:.0f} B/s"
    ax.yaxis.set_major_formatter(mticker.FuncFormatter(_fmt))


# ---------------------------------------------------------------------------
# Core plotting helpers
# ---------------------------------------------------------------------------

def _x_label(ax):
    ax.set_xlabel("Time into test (s)")


def make_figure(title: str) -> tuple[plt.Figure, plt.Axes]:
    fig, ax = plt.subplots()
    ax.set_title(title)
    _x_label(ax)
    return fig, ax


def save(fig: plt.Figure, out_dir: Path, name: str, fmt: str) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"{name}.{fmt}"
    fig.tight_layout()
    fig.savefig(path, bbox_inches="tight")
    plt.close(fig)
    print(f"  saved → {path}")
    return path


# ---------------------------------------------------------------------------
# Metric definitions
# ---------------------------------------------------------------------------

def build_metrics(step: str) -> list[dict]:
    """
    Each entry describes one output chart.

    Keys:
      title       – chart title
      name        – output filename (no extension)
      ylabel      – y-axis label string
      unit        – one of: percentunit, bytes, ms, s, Bps, reqps, ops, short
      series      – list of {expr, legend_tmpl} dicts.
                    legend_tmpl may contain {adapter} and {label} placeholders.
                    If it contains quantile markers (p50/p95/p99) they get
                    distinct line styles automatically.
      post_fmt    – optional callable(ax) to apply custom y-axis formatting
    """
    return [
        # --- k6 round-trip times ---
        {
            "title": "k6 - First Render RTT",
            "name": "k6_first_render_rtt",
            "ylabel": "Latency",
            "unit": "s",
            "post_fmt": seconds_formatter,
            "series": [
                {"expr": "histogram_quantile(0.50, k6_first_render_rtt_ms_seconds)", "label": "p50"},
                {"expr": "histogram_quantile(0.95, k6_first_render_rtt_ms_seconds)", "label": "p95"},
                {"expr": "histogram_quantile(0.99, k6_first_render_rtt_ms_seconds)", "label": "p99"},
            ],
        },
        {
            "title": "k6 - Stash RTT",
            "name": "k6_stash_rtt",
            "ylabel": "Latency",
            "unit": "s",
            "post_fmt": seconds_formatter,
            "per_adapter": True,
            "series": [
                {"expr": "histogram_quantile(0.50, sum(k6_stash_rtt_ms_seconds))", "label": "p50"},
                {"expr": "histogram_quantile(0.95, sum(k6_stash_rtt_ms_seconds))", "label": "p95"},
                {"expr": "histogram_quantile(0.99, sum(k6_stash_rtt_ms_seconds))", "label": "p99"},
            ],
        },
        {
            "title": "k6 - Reconnect RTT",
            "name": "k6_reconnect_rtt",
            "ylabel": "Latency",
            "unit": "s",
            "post_fmt": seconds_formatter,
            "per_adapter": True,
            "series": [
                {"expr": "histogram_quantile(0.50, sum(k6_reconnect_rtt_ms_seconds))", "label": "p50"},
                {"expr": "histogram_quantile(0.95, sum(k6_reconnect_rtt_ms_seconds))", "label": "p95"},
                {"expr": "histogram_quantile(0.99, sum(k6_reconnect_rtt_ms_seconds))", "label": "p99"},
            ],
        },
        # --- BEAM ---
        {
            "title": "BEAM - Scheduler Utilization",
            "name": "beam_scheduler_utilization",
            "ylabel": "Utilization",
            "unit": "percentunit",
            "post_fmt": percent_formatter,
            "series": [
                {"expr": "testing_scheduler_utilization_average", "label": None},
            ],
        },
        {
            "title": "BEAM - Process Count",
            "name": "beam_process_count",
            "ylabel": "Processes",
            "unit": "short",
            "series": [
                {"expr": "testing_prom_ex_beam_stats_process_count", "label": None},
            ],
        },
        {
            "title": "BEAM - Binary Memory",
            "name": "beam_binary",
            "ylabel": "Memory",
            "unit": "bytes",
            "post_fmt": bytes_formatter,
            "series": [
                {"expr": "testing_prom_ex_beam_memory_binary_total_bytes", "label": None},
            ],
        },
        {
            "title": "BEAM - ETS Memory",
            "name": "beam_ets",
            "ylabel": "Memory",
            "unit": "bytes",
            "post_fmt": bytes_formatter,
            "series": [
                {"expr": "testing_prom_ex_beam_memory_ets_total_bytes", "label": None},
            ],
        },
        {
            "title": "BEAM - Port Input",
            "name": "beam_input",
            "ylabel": "Throughput",
            "unit": "Bps",
            "post_fmt": bps_formatter,
            "port_io_direction": "input",
        },
        {
            "title": "BEAM - Port Output",
            "name": "beam_output",
            "ylabel": "Throughput",
            "unit": "Bps",
            "post_fmt": bps_formatter,
            "port_io_direction": "output",
        },
        # --- LiveStash ---
        {
            "title": "LiveStash - Stash Rate (Called vs Executed)",
            "name": "livestash_stash_rate",
            "ylabel": "req/s",
            "unit": "reqps",
            "per_adapter": True,
            "series": [
                {"expr": "sum by (adapter) (rate(live_stash_stash_called_total[1m]))",   "label": "called",   "filter_by": "adapter"},
                {"expr": "sum by (adapter) (rate(live_stash_stash_executed_total[1m]))", "label": "executed", "filter_by": "adapter"},
            ],
        },
        {
            "title": "LiveStash - Recover State Rate by Status",
            "name": "livestash_recover_state",
            "ylabel": "req/s",
            "unit": "reqps",
            "per_adapter": True,
            "series": [
                {"expr": "sum by (status) (rate(live_stash_recover_state_total[1m]))", "label": "{prom_label}"},
            ],
        },
        # --- Infrastructure ---
        {
            "title": "Node - CPU Utilization",
            "name": "node_cpu",
            "ylabel": "CPU",
            "unit": "percentunit",
            "post_fmt": percent_formatter,
            "series": [
                {"expr": "1 - avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[1m]))", "label": None},
            ],
        },
        {
            "title": "Node - Memory Used",
            "name": "node_memory",
            "ylabel": "Memory",
            "unit": "bytes",
            "post_fmt": bytes_formatter,
            "series": [
                {"expr": "node_memory_active_bytes + node_memory_wired_bytes + node_memory_compressed_bytes or node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes", "label": None},
            ],
        },
        {
            "title": "Redis - Operations/sec",
            "name": "redis_ops",
            "require_tag": "redis",
            "ylabel": "ops/s",
            "unit": "ops",
            "series": [
                {"expr": "rate(redis_commands_processed_total[1m])", "label": None},
            ],
        },
        {
            "title": "Redis - Memory Used",
            "name": "redis_memory",
            "require_tag": "redis",
            "ylabel": "Memory",
            "unit": "bytes",
            "post_fmt": bytes_formatter,
            "series": [
                {"expr": "redis_memory_used_bytes",     "label": "used"},
                {"expr": "redis_memory_used_rss_bytes", "label": "rss"},
            ],
        },
        {
            "title": "Redis - Connected Clients",
            "name": "redis_clients",
            "require_tag": "redis",
            "ylabel": "Clients",
            "unit": "short",
            "series": [
                {"expr": "redis_connected_clients", "label": "connected"},
                {"expr": "redis_blocked_clients",   "label": "blocked"},
            ],
        },
        {
            "title": "Redis - Keyspace Hit Ratio",
            "name": "redis_hit_ratio",
            "require_tag": "redis",
            "ylabel": "Hit ratio",
            "unit": "percentunit",
            "post_fmt": percent_formatter,
            "series": [
                {"expr": "rate(redis_keyspace_hits_total[1m]) / clamp_min(rate(redis_keyspace_hits_total[1m]) + rate(redis_keyspace_misses_total[1m]), 1)", "label": None},
            ],
        },
        {
            "title": "Redis - Network I/O",
            "name": "redis_network_io",
            "require_tag": "redis",
            "ylabel": "Throughput",
            "unit": "Bps",
            "post_fmt": bps_formatter,
            "series": [
                {"expr": "rate(redis_net_input_bytes_total[1m])",  "label": "rx"},
                {"expr": "rate(redis_net_output_bytes_total[1m])", "label": "tx"},
            ],
        },
        {
            "title": "Redis - Command Latency (avg)",
            "name": "redis_cmd_latency",
            "require_tag": "redis",
            "ylabel": "Latency",
            "unit": "s",
            "post_fmt": seconds_formatter,
            "series": [
                {"expr": "rate(redis_commands_duration_seconds_total[1m]) / clamp_min(rate(redis_commands_total[1m]), 1)", "label": "{prom_label}"},
            ],
        },
    ]


# ---------------------------------------------------------------------------
# Label helpers
# ---------------------------------------------------------------------------

QUANTILE_KEYS = ("p50", "p95", "p99")


def _is_quantile_series(series_list: list[dict]) -> bool:
    labels = [s.get("label", "") or "" for s in series_list]
    return all(l in QUANTILE_KEYS for l in labels)


def _adapter_kind(label: str) -> str:
    """Map a run label to an adapter kind for conditional I/O series."""
    l = label.lower()
    if "redis" in l:
        return "redis"
    if "mnesia" in l:
        return "mnesia"
    if "ets" in l:
        return "ets"
    return "baseline"


def _io_components_for_run(label: str) -> list[tuple[str, str]]:
    """Return (component_key, legend_suffix) pairs to plot for a run."""
    kind = _adapter_kind(label)
    components = [("http_ws", "HTTP/WS")]
    if kind in ("ets", "mnesia"):
        components.append(("node", "node"))
    if kind == "redis":
        components.append(("redis", "redis"))
    return components


def _prom_label(result_item: dict) -> str:
    """Best single-word label from Prometheus metric labels."""
    m = result_item["metric"]
    for key in ("status", "adapter", "type", "cmd", "instance", "job"):
        if key in m:
            return m[key]
    # fall back to all labels concatenated
    return " ".join(f"{k}={v}" for k, v in m.items()) or "value"


def _series_line_label(series_def: dict, adapter_label: str, result_item: dict) -> str:
    tmpl = series_def.get("label") or ""
    if tmpl is None or tmpl == "":
        return adapter_label
    if "{prom_label}" in tmpl:
        tmpl = tmpl.replace("{prom_label}", _prom_label(result_item))
    if tmpl in QUANTILE_KEYS:
        return f"{adapter_label} {tmpl}"
    return f"{adapter_label} -{tmpl}"


# ---------------------------------------------------------------------------
# Main chart renderer
# ---------------------------------------------------------------------------

def _plot_chart(
    metric: dict,
    indexed_runs: list[tuple[int, dict]],
    prom_url: str,
    step: str,
    out_dir: Path,
    fmt: str,
    title_suffix: str = "",
    name_suffix: str = "",
) -> bool:
    title = metric["title"] + title_suffix
    print(f"\n[{title}]")

    series_defs = metric["series"]
    quantile_mode = _is_quantile_series(series_defs)

    fig, ax = make_figure(title)
    ax.set_ylabel(metric.get("ylabel", ""))

    plotted = 0

    multi_run = len(indexed_runs) > 1

    for run_idx, run in indexed_runs:
        adapter = run["label"]
        adapter_color = ADAPTER_COLORS[run_idx % len(ADAPTER_COLORS)]
        t_start = parse_iso(run["start"])
        t_end = parse_iso(run["end"])

        for series_def in series_defs:
            expr = series_def["expr"]
            series_label = series_def.get("label") or ""

            try:
                results = query_range(prom_url, expr, t_start, t_end, step)
            except Exception as exc:
                print(f"  WARN: query failed for '{expr}' run={adapter}: {exc}")
                results = []

            if not results:
                print(f"  WARN: no data for '{expr}' (run={adapter})")
                continue

            filter_by = series_def.get("filter_by")
            if filter_by and not multi_run:
                run_name = run.get("prom_name") or run["label"].lower()
                results = [r for r in results if r["metric"].get(filter_by, "").lower() == run_name]
                if not results:
                    print(f"  WARN: no data after filtering {filter_by}={run_name!r}")
                    continue

            for result_item in results:
                xs, ys = series_to_xy(result_item, t_start)
                if len(xs) == 0:
                    continue

                line_label = _series_line_label(series_def, adapter, result_item)

                if quantile_mode and series_label in QUANTILE_KEYS:
                    ls, alpha = QUANTILE_STYLES[series_label]
                elif "linestyle" in series_def:
                    ls, alpha = series_def["linestyle"], 0.9
                else:
                    ls, alpha = "-", 0.9

                # multi-run: fix color per adapter so runs stay visually consistent
                # single-run: let matplotlib cycle so each series line gets its own color
                color_kw = {"color": adapter_color} if multi_run else {}
                ax.plot(xs, ys, **color_kw, linestyle=ls, alpha=alpha, label=line_label)
                plotted += 1

    if plotted == 0:
        print("  WARN: no data -skipping chart")
        plt.close(fig)
        return False

    ax.legend(loc="upper left", ncol=max(1, len(indexed_runs)))
    ax.set_xlim(left=0)

    post_fmt = metric.get("post_fmt")
    if post_fmt:
        post_fmt(ax)

    save(fig, out_dir, metric["name"] + name_suffix, fmt)
    return True


def _plot_port_io_chart(
    metric: dict,
    runs: list[tuple[int, dict]],
    prom_url: str,
    step: str,
    out_dir: Path,
    fmt: str,
) -> bool:
    direction = metric["port_io_direction"]
    exprs = PORT_IO_EXPRS[direction]
    title = metric["title"]
    print(f"\n[{title}]")

    fig, ax = make_figure(title)
    ax.set_ylabel(metric.get("ylabel", ""))

    plotted = 0

    for run_idx, run in runs:
        adapter = run["label"]
        adapter_color = ADAPTER_COLORS[run_idx % len(ADAPTER_COLORS)]
        t_start = parse_iso(run["start"])
        t_end = parse_iso(run["end"])

        for component_key, component_label in _io_components_for_run(adapter):
            expr = exprs[component_key]
            line_label = f"{adapter} {component_label}"
            ls, alpha = IO_COMPONENT_STYLE[component_key]

            try:
                results = query_range(prom_url, expr, t_start, t_end, step)
            except Exception as exc:
                print(f"  WARN: query failed for '{expr}' run={adapter}: {exc}")
                continue

            if not results:
                print(f"  WARN: no data for '{component_label}' (run={adapter})")
                continue

            xs, ys = series_to_xy(results[0], t_start)
            if len(xs) == 0:
                continue

            ax.plot(xs, ys, color=adapter_color, linestyle=ls, alpha=alpha, label=line_label)
            plotted += 1

    if plotted == 0:
        print("  WARN: no data -skipping chart")
        plt.close(fig)
        return False

    ax.legend(loc="upper left", ncol=2)
    ax.set_xlim(left=0)

    post_fmt = metric.get("post_fmt")
    if post_fmt:
        post_fmt(ax)

    save(fig, out_dir, metric["name"], fmt)
    return True


def render_metric(metric: dict, runs: list[dict], prom_url: str, step: str, out_dir: Path, fmt: str) -> int:
    require_tag = metric.get("require_tag")
    active = [
        (i, run) for i, run in enumerate(runs)
        if not require_tag or require_tag in (run.get("tags") or [])
    ]

    if not active:
        print(f"\n[{metric['title']}] skipped - no runs have tag {require_tag!r}")
        return 0

    if metric.get("port_io_direction"):
        saved = _plot_port_io_chart(metric, active, prom_url, step, out_dir, fmt)
        return 1 if saved else 0

    saved = 0
    if metric.get("per_adapter"):
        for run_idx, run in active:
            slug = run["label"].lower().replace(" ", "_")
            if _plot_chart(metric, [(run_idx, run)], prom_url, step, out_dir, fmt,
                           title_suffix=f" - {run['label']}",
                           name_suffix=f"_{slug}"):
                saved += 1
    elif _plot_chart(metric, active, prom_url, step, out_dir, fmt):
        saved += 1
    return saved


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("runs", nargs="?", default="runs.csv",
                        help="runs.csv or legacy runs.yaml (default: runs.csv)")
    parser.add_argument("--config", "-c", default=None,
                        help="Settings YAML (default: chart_config.yaml beside runs.csv)")
    parser.add_argument("--group", "-g", default=None,
                        help="CSV only: filter rows by group column")
    parser.add_argument("--out", default="output", help="Output directory (default: output/)")
    parser.add_argument("--step", default=None, help="Prometheus step override (e.g. 15s)")
    parser.add_argument("--prometheus-url", default=None, help="Prometheus base URL override")
    parser.add_argument("--format", default="png", choices=["png", "svg", "pdf"], dest="fmt")
    parser.add_argument("--metrics", nargs="*", help="Restrict to these metric names (by 'name' key)")
    args = parser.parse_args()

    runs_path = Path(args.runs)
    if not runs_path.exists():
        sys.exit(f"Runs file not found: {runs_path}")

    config_path = Path(args.config) if args.config else None
    settings, runs = load_config(runs_path, config_path, args.group)

    prom_url = args.prometheus_url or settings.get("prometheus_url", "http://localhost:9090")
    step = args.step or settings.get("step", "5s")
    out_dir = Path(args.out)
    active_group = args.group or settings.get("default_group")

    if not runs:
        group_hint = f" (group={active_group!r})" if active_group else ""
        sys.exit(f"No completed runs found in {runs_path}{group_hint}")

    print(f"Prometheus : {prom_url}")
    print(f"Step       : {step}")
    if active_group:
        print(f"Group      : {active_group}")
    print(f"Runs       : {[r['label'] for r in runs]}")
    print(f"Output     : {out_dir}/  (.{args.fmt})")

    matplotlib.rcParams.update(ARTICLE_STYLE)

    all_metrics = build_metrics(step)
    if args.metrics:
        all_metrics = [m for m in all_metrics if m["name"] in args.metrics]
        if not all_metrics:
            sys.exit(f"No metrics matched: {args.metrics}")

    saved_total = 0
    for metric in all_metrics:
        saved_total += render_metric(metric, runs, prom_url, step, out_dir, args.fmt)

    print(f"\nDone — {saved_total} charts written to {out_dir}/")


if __name__ == "__main__":
    main()

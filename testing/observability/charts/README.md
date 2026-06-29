Usage

# activate venv

```
python3 -m venv .venv
source .venv/bin/activate
pip install requests matplotlib pyyaml numpy
```

# 1. run load tests (load VM)

clear logs
`ssh root@46.62.151.189 'cp /opt/k6/runs.csv /opt/k6/runs.csv.bak 2>/dev/null; printf "%s\n" "run_id,group,label,adapter,base_path,ttl_s,vus,cleanup_s,size_kb,tags,start,end,notes" > /opt/k6/runs.csv'`

`run_matrix.sh` sets app TTL/cleanup, runs k6, logs to `/opt/k6/runs.csv`:

```
/opt/k6/run_matrix.sh --ttl 60 --vus 1000 --adapter all
/opt/k6/run_matrix.sh --ttl 60 --matrix
/opt/k6/run_matrix.sh --matrix-full
```

Each group is named like `ttl60s-vus1000` (or `ttl900s-vus1000-cleanup450s`).

# 2. copy runs.csv back

```
scp -P 2222 root@LOAD_VM:/opt/k6/runs.csv testing/observability/charts/
```

# 3. generate charts

```
./generate_charts.sh --group ttl60s-vus1000
./generate_charts.sh --format svg --metrics beam_scheduler_utilization node_cpu
```

Settings: `chart_config.yaml` (`prometheus_url`, `step`, `default_group`, `app_node_instances`).

# env vars (app VMs)

| Variable | Default | Description |
|----------|---------|-------------|
| `LIVE_STASH_TTL` | 60 | LiveView stash TTL (seconds) |
| `LIVE_STASH_ETS_CLEANUP_INTERVAL_MS` | 30000 | ETS cleaner interval |
| `LIVE_STASH_MNESIA_CLEANUP_INTERVAL_MS` | 30000 | Mnesia cleaner interval |

Set manually via  ansible 
```bash
cd testing/deploy/ansible
ansible-playbook site.yml --tags app \
  -e live_stash_ttl=60 \
  -e live_stash_cleanup_interval_s=30.
```

# k6 defaults (must match app TTL)

| Variable | Default |
|----------|---------|
| `TTL` | 60 |
| `SIZE_KB` | 5 |
| `TEST_DURATION_SEC` | 180 / 600 / 1500 for TTL 60 / 300 / 900 |
| `RECONNECT_WITHIN_TTL_PCT` | 40 |

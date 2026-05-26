# Observability — local Prometheus + Grafana

Local setup that scrapes the running `testing/` Phoenix app and renders the
PromEx dashboards in Grafana.

## Architecture

```
┌─────────────────────────────────────────────────┐
│ Host machine                                    │
│                                                 │
│  mix phx.server                                 │
│  http://localhost:4000/metrics  ◄──┐            │
│                                    │            │
│  ┌──────────────────────────────┐  │ scrape     │
│  │ docker compose:              │  │ every 5s   │
│  │                              │  │            │
│  │  Prometheus :9090  ──────────┘            │
│  │       ▲                      │            │
│  │       │ query                │            │
│  │       │                      │            │
│  │  Grafana :3000                │            │
│  │  (datasource + dashboards    │            │
│  │   auto-provisioned)          │            │
│  └──────────────────────────────┘            │
└─────────────────────────────────────────────────┘
```

`host.docker.internal` is how the Prometheus container reaches the Phoenix
app on the host. Works out of the box on Docker Desktop (Mac/Windows); on
Linux the `extra_hosts: host-gateway` line in `docker-compose.yml` makes
it work too.

## Run

```sh
# Terminal A — the app being measured
cd ../  # i.e. the testing/ project root
mix phx.server

# Terminal B — observability stack
cd observability/
docker-compose up -d
```

Then:

- Prometheus UI: <http://localhost:9090> — `Status → Targets` should show
  `testing_app` as `UP`.
- Grafana UI: <http://localhost:3000> — anonymous viewer access enabled
  (admin/admin to log in for editing). Dashboards under `Dashboards →
  PromEx` folder.

## Stop / reset

```sh
docker-compose down            # stop, keep data
docker-compose down -v         # also wipe prometheus/grafana state
```

## Refreshing dashboards after changing PromEx plugins

The JSON files in `grafana/dashboards/` are rendered snapshots from PromEx.
After adding/removing plugins, re-export:

```sh
cd ../  # testing/
for d in beam phoenix phoenix_live_view application; do
  mix prom_ex.dashboard.export -d "${d}.json" -m Testing.PromEx --stdout \
    > "observability/grafana/dashboards/${d}.json"
done
```

The Grafana provisioning watcher reloads files every 30s — no restart
needed.

## Adding new scrape targets later

For the multi-node load test setup, add more entries to
`prometheus/prometheus.yml`:

```yaml
- job_name: testing_cluster
  static_configs:
    - targets:
        - node_a.internal:4000
        - node_b.internal:4000
        - node_c.internal:4000
```

For node_exporter (host OS metrics) or redis_exporter, follow the same
pattern with their respective ports (9100, 9121).

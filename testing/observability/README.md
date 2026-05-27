# Observability — Prometheus + Grafana

Scrapes the `testing/` Phoenix app, node_exporter, and redis_exporter and
renders the PromEx + load-test dashboards in Grafana.

## Architecture

Three "VM-role" compose files under `testing/`, each self-contained so the
same files deploy to a single host (locally) or to separate VMs:

- `docker-compose.app.yml` — app + node_exporter (ports 4000, 9100)
- `docker-compose.redis.yml` — redis + redis_exporter (ports 6379, 9121)
- `observability/docker-compose.yml` — prometheus + grafana + nginx (9090, 3000, 80)

Prometheus reaches the other services via `host.docker.internal:<port>`
locally (the published ports show up on the host), or via VM IPs in
production (see the commented blocks in `prometheus/prometheus.yml`).

## Run — single host (local)

```sh
cd testing/
SECRET_KEY_BASE=$(mix phx.gen.secret) docker compose up -d --build
```

The top-level `testing/docker-compose.yml` `include:`s all three role files.

## Run — per VM

```sh
# App VM(s)
docker compose -f docker-compose.app.yml up -d --build

# Redis VM
docker compose -f docker-compose.redis.yml up -d

# Observability VM (after editing prometheus.yml targets to point at the
# app/redis VM IPs)
docker compose -f observability/docker-compose.yml up -d
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

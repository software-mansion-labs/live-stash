# Testing

A Phoenix app used as a load-test harness for `live_stash`. Bundles the app,
redis, observability (Prometheus + Grafana + nginx) and a k6 load driver, all
runnable as a single docker-compose stack.

## Run the full stack (docker)

The stack is split into per-role compose files so the same files deploy to
single host or multiple VMs (see `observability/README.md`).

```sh
# from testing/
docker-compose up -d --build
```

Brings up: app (`:4000`), node_exporter (`:9100`), redis (`:6379`),
redis_exporter (`:9121`), prometheus (`:9090`), grafana (`:3000`), nginx
(`:80`).

- App: <http://localhost:4000>
- Grafana: <http://localhost:3000> — `Dashboards → livestash load test`
- Prometheus targets: <http://localhost:9090/targets>

`SECRET_KEY_BASE` is read from `testing/.env` (auto-loaded by docker-compose;
gitignored). Generate a fresh one with `mix phx.gen.secret` if it's missing.

Stop / wipe:

```sh
docker-compose down            # stop, keep volumes (prom + grafana state)
docker-compose down -v         # also wipe volumes
```

## Run a load test (k6)

The k6 driver lives in `docker-compose.k6.yml`, gated behind the `k6` profile
so it never auto-starts with `up`. Each invocation is one fresh test run.

```sh
docker-compose -f docker-compose.k6.yml --profile k6 run --rm k6
```

Override knobs per run:

```sh
docker-compose -f docker-compose.k6.yml --profile k6 run --rm \
  -e SIZE_KB=1000 -e VUS=100 -e BASE_PATH=/performance/baseline k6
```

See `k6/README.md` for scenario details and the full env-var table.

## Develop on the host (no docker)

Useful for hot reload / `iex -S mix`:

```sh
mix setup            # deps + assets
mix phx.server       # or: iex -S mix phx.server
```

Visit <http://localhost:4000>. The observability stack and redis can still
run via docker; Prometheus reaches the host app through
`host.docker.internal:4000`.

## Learn more

* Phoenix: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html

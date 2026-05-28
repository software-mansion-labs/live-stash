# k6 Load Tests

Load tests for the `testing/` Phoenix app using [k6](https://k6.io).

## Prerequisites

- Either k6 installed on the host (`brew install k6`) **or** Docker
- `testing/` stack running: `docker-compose up -d` in `testing/`

## Run — in Docker (recommended for parity with the load-test stack)

The k6 service joins the compose network and reaches the app via its service
name (skipping the docker-proxy hop), and sends metrics straight to
prometheus.

```sh
docker-compose -f docker-compose.k6.yml --profile k6 run --rm k6
```

Override vars per run:

```sh
docker-compose -f docker-compose.k6.yml --profile k6 run --rm \
  -e SIZE_KB=1000 -e VUS=100 -e BASE_PATH=/performance/baseline k6
```

## Run — on the host

```sh
# Console output only
k6 run testing/k6/load_test.js

# With Prometheus remote write (sends k6 metrics to Grafana)
K6_PROMETHEUS_RW_SERVER_URL=http://localhost:9090/api/v1/write \
K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM=true \
  k6 run --out=experimental-prometheus-rw testing/k6/load_test.js
```

### Options

| Variable                    | Default                      | Description                                                       |
| --------------------------- | ---------------------------- | ----------------------------------------------------------------- |
| `HOST`                      | `localhost:4000`             | Host and port of the Phoenix app                                  |
| `SIZE_KB`                   | `100`                        | Payload size in KB                                                |
| `BASE_PATH`                 | `/performance/livestash_ets` | Which live view to test                                           |
| `VUS`                       | `50`                         | Peak concurrent virtual users                                     |
| `TTL`                       | `5`                          | Adapter TTL in seconds (must match `:ttl` on the LiveView module) |
| `RECONNECT_WITHIN_TTL_PCT`  | `80`                         | % of iterations that reconnect while the stash is still alive     |
| `TEST_DURATION_SEC`         | `300`                        | Total test duration (incl. ramp up/down)                          |
| `RAMP_UP_SEC`               | `30`                         | Ramp-up duration                                                  |
| `RAMP_DOWN_SEC`             | `30`                         | Ramp-down duration                                                |
| `SOCKET_TIMEOUT_MS`         | `60000`                      | Per-socket safety timeout                                         |

```sh
# LiveStash ETS (default)
k6 run testing/k6/load_test.js

# Baseline (no LiveStash)
k6 run -e BASE_PATH=/performance/baseline testing/k6/load_test.js

# Custom payload size
k6 run -e BASE_PATH=/performance/baseline -e SIZE_KB=1000 testing/k6/load_test.js

K6_PROMETHEUS_RW_SERVER_URL=http://localhost:9090/api/v1/write \
K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM=true \
  k6 run -e BASE_PATH=/performance/baseline -e SIZE_KB=1000 --out=experimental-prometheus-rw testing/k6/load_test.js
```

## Scenario

Per VU iteration:

1. HTTP GET → grab CSRF token, `phx-session`, `phx-static`, `phx-id`.
2. **Connection 1** — `phx_join` (fresh mount), wait ~5 s, `regenerate` (stash),
   wait ~15 s, close.
3. **Gap** — `RECONNECT_WITHIN_TTL_PCT` % of iterations wait less than `TTL`
   (stash still recoverable); the rest wait `TTL + 1..3 s` (stash expired,
   fresh mount on reconnect).
4. **Connection 2** — `phx_join` (with `liveStash.stashId`), wait ~15 s,
   `regenerate` again (second stash on the same connection), wait ~15 s, close.

All sleeps are jittered ±20 % so VUs don't re-synchronise.

Load profile: ramp to `VUS` over `RAMP_UP_SEC`, hold, ramp down over
`RAMP_DOWN_SEC` — total `TEST_DURATION_SEC` (default 5 min).

## Metrics

| Metric                | Tags                          | Description                                                    |
| --------------------- | ----------------------------- | -------------------------------------------------------------- |
| `first_render_rtt_ms` |                               | RTT from `phx_join` (conn 1) to first rendered diff            |
| `stash_rtt_ms`        | `stash_round=1\|2`            | RTT from `regenerate` to diff (per stash round in the iter)    |
| `reconnect_rtt_ms`    | `within_ttl=true\|false`      | RTT from `phx_join` (conn 2) — split by whether stash was live |

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

| Variable                   | Default                      | Description                                                       |
| -------------------------- | ---------------------------- | ----------------------------------------------------------------- |
| `HOST`                     | `localhost:4000`             | Host and port of the Phoenix app                                  |
| `SIZE_KB`                  | `5`                          | Payload size in KB                                                |
| `BASE_PATH`                | `/performance/livestash_ets` | Which live view to test                                           |
| `VUS`                      | `50`                         | Peak concurrent virtual users                                     |
| `TTL`                      | `60`                         | Adapter TTL in seconds (must match `LIVE_STASH_TTL` on the app)   |
| `RECONNECT_WITHIN_TTL_PCT` | `40`                         | % of iterations that reconnect while the stash is still alive     |
| `TEST_DURATION_SEC`        | auto from TTL                | 180 / 600 / 1500 for TTL 60 / 300 / 900                           |
| `RAMP_UP_SEC`              | `30`                         | Ramp-up duration                                                  |
| `RAMP_DOWN_SEC`            | `30`                         | Ramp-down duration                                                |
| `SOCKET_TIMEOUT_MS`        | auto from waits              | Per-socket safety timeout                                         |

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

| Metric                | Tags                     | Description                                                    |
| --------------------- | ------------------------ | -------------------------------------------------------------- |
| `first_render_rtt_ms` |                          | RTT from `phx_join` (conn 1) to first rendered diff            |
| `stash_rtt_ms`        | `stash_round=1\|2`       | RTT from `regenerate` to diff (per stash round in the iter)    |
| `reconnect_rtt_ms`    | `within_ttl=true\|false` | RTT from `phx_join` (conn 2) — split by whether stash was live |

## Known limit: the Mac

Running the app **and** k6 together in a local Mac container VM (Colima / Docker
Desktop) hits a wall around ~1500–2000 concurrent connections, then collapses
all at once — a burst of `connection refused`, `1006 abnormal closure`, and
`write: broken pipe` errors in the same instant. **This is the virtualization
layer, not LiveStash or Phoenix.**

The tell is the host **load average sitting at 2–5 on a 2-core VM while
container CPU is ~0 %** — threads are blocked in I/O wait on the emulated
(virtio) network, not CPU-bound. All containers share the VM's few vCPUs, which
also run the kernel's per-packet softirq + virtio emulation for thousands of
connections moving 100 KB payloads. The accept queue, fds, conntrack, and app
CPU all stay healthy; the VM's I/O path is the bottleneck.

What helps vs. what doesn't:

- **Give the VM more cores** (Colima: `colima stop && colima start --cpu 6
--memory 12`, leaving ~2 cores for macOS). Raises the ceiling to a few
  thousand — fine for local iteration.
- **It will not produce a valid 5k benchmark.** The physical core count,
  irreducible virtio overhead, and k6 sharing the VM with the app (stealing its
  cores) all skew the result.
- **For real high-VU numbers: two separate _Linux_ hosts** — app on one, k6 on
  another, over the network. Never co-locate the load generator with the target.

The container-side tuning (`nofile`/`somaxconn` in `docker-compose.app.yml`,
Bandit `thousand_island_options` in `config/runtime.exs`, k6 fd/port sysctls in
`docker-compose.k6.yml`) is correct and necessary — it just isn't the limiter on
a Mac VM.

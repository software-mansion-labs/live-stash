# k6 Load Tests

Load tests for the `testing/` Phoenix app using [k6](https://k6.io).

## Prerequisites

- [k6 installed](https://grafana.com/docs/k6/latest/set-up/install-k6/) (`brew install k6` on macOS)
- `testing/` Phoenix app running (`mix phx.server` in `testing/`)
- Observability stack running (optional, for Grafana dashboards)

## Run

```sh
k6 run testing/k6/load_test.js
```

### Options

| Variable     | Default                      | Description                        |
|--------------|------------------------------|------------------------------------|
| `HOST`       | `localhost:4000`             | Host and port of the Phoenix app   |
| `SIZE_KB`    | `100`                        | Payload size in KB                 |
| `BASE_PATH`  | `/performance/livestash_ets` | Which live view to test            |
| `VUS`        | `50`                         | Number of concurrent virtual users |
| `ITERATIONS` | `5000`                       | Total iterations shared across VUs |

```sh
# LiveStash ETS (default)
k6 run testing/k6/load_test.js

# Baseline (no LiveStash)
k6 run -e BASE_PATH=/performance/baseline testing/k6/load_test.js

# Custom payload size
k6 run -e BASE_PATH=/performance/baseline -e SIZE_KB=1000 testing/k6/load_test.js
```

## Scenarios

**`load_test.js`** — tests `LiveStashEtsLive` (`/performance/livestash_ets`):

1. HTTP GET to grab CSRF token, `phx-session`, `phx-static`, `phx-id`
2. WebSocket upgrade to `/live/websocket`
3. `phx_join` → measures **`first_render_rtt_ms`** (time to first rendered diff)
4. `regenerate` click event → measures **`stash_rtt_ms`** (time to ETS stash + diff)

Default load profile: ramp to 50 VUs over 30s, hold for 60s, ramp down.

## Metrics

| Metric               | Description                                      |
|----------------------|--------------------------------------------------|
| `first_render_rtt_ms` | RTT from `phx_join` to receiving the initial render |
| `stash_rtt_ms`        | RTT from sending `regenerate` to receiving the diff |

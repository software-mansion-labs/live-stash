# Bare-VM deployment (no containers)

Run the same load-test scenario as the local Docker stack, but natively across
a few VMs. These are artifacts with placeholder IPs.

Replace every `APP_VM_1`, `APP_VM_2`, `REDIS_VM`, `OBS_VM` placeholder with real
host IPs/DNS names.

## Topology

Two clustered app VMs behind an nginx load balancer (on the obs VM). k6 hits
nginx, so reconnects round-robin across the nodes — which is what exercises ETS
node-hint and Mnesia cross-node recovery.

```
   load (k6) ──▶ obs:80 (nginx LB) ──┬──▶ APP_VM_1:4000
                                      └──▶ APP_VM_2:4000  ──▶ REDIS_VM:6379
   obs: Prometheus (scrapes both app nodes directly) + Grafana
```

| VM       | Runs                                                  | Notes                                        |
| -------- | ----------------------------------------------------- | -------------------------------------------- |
| `app` ×2 | Phoenix release + `node_exporter`                     | clustered; add APP_VM_3+ the same way        |
| `redis`  | Redis + `redis_exporter` + `node_exporter`            | only needed for the redis adapter            |
| `obs`    | Prometheus + Grafana + **nginx LB** + `node_exporter` | single entry point; receives k6 remote-write |
| `load`   | k6                                                    | kept separate                                |

No code changes: the k6 script and the app are already env-driven. This is wiring and OS tuning only.

## App VM

1. Install Erlang/Elixir, build a release from the repo root:
   ```sh
   cd testing && MIX_ENV=prod mix release
   ```
   Copy `_build/prod/rel/testing` to the VM at `/opt/livestash`.
2. `cp app.env.example /etc/livestash/app.env` and fill it in. **Each app VM
   gets its own `RELEASE_NODE`** (`testing@APP_VM_1`, `testing@APP_VM_2`); the
   `RELEASE_COOKIE` and everything else are identical across nodes.
3. Install the service + tuning:
   ```sh
   sudo cp systemd/livestash-app.service /etc/systemd/system/
   sudo cp sysctl/99-livestash-app.conf /etc/sysctl.d/   && sudo sysctl --system
   sudo cp limits.d/99-livestash.conf  /etc/security/limits.d/
   sudo systemctl daemon-reload && sudo systemctl enable --now livestash-app
   ```
   `LimitNOFILE=1048576` and `Restart=on-failure` are in the unit; `somaxconn`
   and `tcp_max_syn_backlog` are in the sysctl file. The Bandit
   `thousand_island_options` tuning is already in `config/runtime.exs`.

## Redis VM

Install Redis natively, bind to the VM IP (`bind 0.0.0.0` or the private IP),
and point the app at it via `LIVE_STASH_REDIS_URL` in `app.env`. Run
`redis_exporter` (see `systemd/redis_exporter.service`).

## Obs VM (Prometheus + Grafana + nginx LB)

Install Prometheus, Grafana, and nginx natively.

- Prometheus: use `prometheus.vm.yml` (fill in IPs; it scrapes both app nodes
  directly for per-node metrics, not through nginx).
- Grafana: copy the existing `observability/grafana/dashboards/*.json` and
  `observability/grafana/provisioning/`, but use `grafana-datasource.vm.yml`
  (points at `localhost:9090` instead of the `prometheus` service name).
- nginx (the load balancer):
  ```sh
  sudo cp nginx/livestash.conf /etc/nginx/conf.d/   # fill in APP_VM_* IPs
  sudo rm -f /etc/nginx/sites-enabled/default        # drop the default site
  sudo nginx -t && sudo systemctl reload nginx
  ```

## Load VM

```sh
sudo cp sysctl/99-livestash-load.conf /etc/sysctl.d/ && sudo sysctl --system
sudo cp limits.d/99-livestash.conf    /etc/security/limits.d/
# Hits the nginx LB on the obs VM by default; fans out to the app cluster.
OBS_VM=OBS_VM ./run-k6.sh -e BASE_PATH=/performance/livestash_redis
```

Clustering is enabled in `app.env.example`
(`RELEASE_DISTRIBUTION`/`RELEASE_NODE`/`RELEASE_COOKIE`/`DNS_CLUSTER_QUERY`).
`DNS_CLUSTER_QUERY` must resolve to **all** app VM IPs (internal/headless DNS
record). Open EPMD (4369) + the Erlang distribution port range between app VMs.
To sanity-check the cluster formed: `bin/testing remote` then `Node.list()`
should list the other node(s).

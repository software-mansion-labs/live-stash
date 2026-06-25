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
   load VM: k6 ──▶ 127.0.0.1:80 (nginx LB) ──┬──▶ 10.10.0.3:4000 (app-1)
                                              └──▶ 10.10.0.4:4000 (app-2) ──▶ 10.10.0.5:6379 (redis)
   obs VM (10.10.0.2): Prometheus (scrapes both app nodes directly) + Grafana
```

| VM       | IP        | Runs                                       | Notes                                          |
| -------- | --------- | ------------------------------------------ | ---------------------------------------------- |
| `app-1`  | 10.10.0.3 | Phoenix release + `node_exporter`          | clustered; add app-3+ the same way             |
| `app-2`  | 10.10.0.4 | Phoenix release + `node_exporter`          | clustered                                      |
| `redis`  | 10.10.0.5 | Redis + `redis_exporter` + `node_exporter` | only needed for the redis adapter              |
| `obs`    | 10.10.0.2 | Prometheus + Grafana + `node_exporter`     | receives k6 remote-write                        |
| `load`   | 10.10.0.6 | k6 + **nginx LB**                          | biggest box, so the LB won't bottleneck        |

No code changes: the k6 script and the app are already env-driven. This is wiring and OS tuning only.

## Building the release on macOS

`mix release` bundles the compiled BEAM files **plus the ERTS and native
binaries for the build machine's OS/arch**. A release built on macOS (arm64)
will not run on these Debian x86 VMs. Build a Linux x86 release one of two ways:

**A. Docker (recommended — uses the existing `testing/Dockerfile`):**
```sh
# from the repo root (live-stash/)
docker build -f testing/Dockerfile --platform linux/amd64 -t livestash-rel .
# copy the release out of the image into ./rel
id=$(docker create --platform linux/amd64 livestash-rel)
docker cp "$id":/app ./rel && docker rm "$id"
tar -C ./rel -czf testing-rel.tgz .
```
Then ship `testing-rel.tgz` to each app VM and unpack into `/opt/livestash`.

**B. Build on one of the app VMs** (Debian x86 already): install Erlang/Elixir
there, `cd testing && MIX_ENV=prod mix release`, then copy
`_build/prod/rel/testing` to `/opt/livestash` on each app VM.

> "Release build" = a self-contained artifact (`bin/testing start`) the systemd
> unit runs. It needs no Elixir/Mix installed on the target VM.

## Firewall (UFW)

All inter-VM traffic uses the private network, so allow the private subnet
wholesale on every VM — this covers app ports (4000), redis (6379), exporters
(9100/9121), Prometheus (9090), EPMD (4369) and the Erlang distribution range,
so there's no need to pin distribution ports:
```sh
sudo ufw allow from 10.0.0.0/8        # private network (covers 10.10.0.0/x)
sudo ufw allow 22/tcp                  # SSH (public)
# obs VM only, if you view Grafana / query Prometheus from your laptop:
sudo ufw allow 3000/tcp
sudo ufw allow 9090/tcp
sudo ufw enable
```
`10.0.0.0/8` is broad but fine since it only matches RFC1918 private addresses;
tighten to `10.10.0.0/24` if you prefer.

## App VM (10.10.0.3, 10.10.0.4)

1. Build a release (must be built for Linux x86 — see "Building on macOS"
   below), and unpack it on the VM at `/opt/livestash`.
2. `cp app.env.example /etc/livestash/app.env` and fill it in. **Each app VM
   gets its own `RELEASE_NODE` and `PHX_HOST`** (its own private IP:
   `testing@10.10.0.3` / `testing@10.10.0.4`); `RELEASE_COOKIE`, `CLUSTER_HOSTS`
   and everything else are identical across nodes.
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

## Obs VM (Prometheus + Grafana) — 10.10.0.2

Install Prometheus and Grafana natively.

- Prometheus: use `prometheus.vm.yml` (scrapes both app nodes directly for
  per-node metrics, not through nginx). Start it with the remote-write receiver
  and native histograms enabled, or k6 metrics won't land:
  ```sh
  prometheus --config.file=prometheus.vm.yml \
    --web.enable-remote-write-receiver --enable-feature=native-histograms
  ```
- Grafana: copy the existing `observability/grafana/dashboards/*.json` and
  `observability/grafana/provisioning/`, but use `grafana-datasource.vm.yml`
  (points at `localhost:9090` instead of the `prometheus` service name).

## Load VM (k6 + nginx LB) — 10.10.0.6

nginx (the LB) lives here, on the biggest box, so it doesn't bottleneck the run.

```sh
sudo cp nginx/livestash.conf /etc/nginx/conf.d/    # IPs already filled in
sudo rm -f /etc/nginx/sites-enabled/default        # drop the default site
sudo nginx -t && sudo systemctl reload nginx

sudo cp sysctl/99-livestash-load.conf /etc/sysctl.d/ && sudo sysctl --system
sudo cp limits.d/99-livestash.conf    /etc/security/limits.d/
# Hits the local nginx LB on this VM's private IP (not 127.0.0.1 — loopback
# runs out of ephemeral ports around 15–20k VUs). Fans out to the app cluster.
HOST=10.10.0.6:80 ./run-k6.sh -e BASE_PATH=/performance/livestash_redis
```

Clustering is enabled in `app.env.example`
(`RELEASE_DISTRIBUTION`/`RELEASE_NODE`/`RELEASE_COOKIE`/`CLUSTER_HOSTS`).
libcluster's Epmd strategy connects to every node in `CLUSTER_HOSTS` (the same
list on every app VM). EPMD (4369) + the Erlang distribution port range must be
reachable between app VMs — a UFW rule allowing the private subnet covers it.
To sanity-check the cluster formed: `bin/testing remote` then `Node.list()`
should list the other node(s).

# Ansible deploy

Provisions the whole LiveStash load-test stack across the 5 Hetzner VMs. It
reuses the static files in `../vm/` (systemd units, sysctl, limits,
grafana-datasource) and templates the IP-bearing ones (app.env, prometheus
config, nginx upstream, run-k6.sh) straight from the inventory.

## Topology (driven entirely by `inventory.ini`)

| Group   | Host  | Public (SSH)   | Private    | Runs                                   |
| ------- | ----- | -------------- | ---------- | -------------------------------------- |
| `app`   | app-1 | 37.27.20.234   | 10.10.0.3  | Phoenix release + node_exporter        |
| `app`   | app-2 | 37.27.3.30     | 10.10.0.4  | Phoenix release + node_exporter        |
| `redis` | redis | 37.27.27.84    | 10.10.0.5  | Redis + redis_exporter + node_exporter |
| `obs`   | obs   | 37.27.16.253   | 10.10.0.2  | Prometheus + Grafana + node_exporter   |
| `load`  | load  | 46.62.151.189  | 10.10.0.6  | k6 + nginx LB (no node_exporter)       |

Add an `app-3` by appending one line to `[app]` — nginx upstream, prometheus
targets, and `CLUSTER_HOSTS` all regenerate from the inventory.

## Prerequisites (on your Mac)

```sh
# 1. Ansible + the ufw collection
brew install ansible
cd testing/deploy/ansible
ansible-galaxy collection install -r requirements.yml

# 2. SSH access to every VM (key-based, as root)
ssh root@46.62.151.189 true   # etc.
```

```sh
# 3 build release
rsync -az --delete -e "ssh -p 2222" \
  --exclude '.git' --exclude '_build' --exclude 'deps' \
  --exclude 'node_modules' --exclude '.venv' \
  ./ root@37.27.20.234:/root/live-stash/

ssh -p 2222 root@37.27.20.234 '
  set -e
  cd /root/live-stash
  docker build -f testing/Dockerfile -t livestash-rel .
  id=$(docker create livestash-rel)
  rm -rf /root/rel
  docker cp "$id":/app /root/rel
  docker rm "$id"
  tar -C /root/rel -czf /root/testing-rel.tgz .
  ls -la /root/testing-rel.tgz
'

scp -P 2222 root@37.27.20.234:/root/testing-rel.tgz \
  testing/deploy/ansible/files/testing-rel.tgz

cd testing/deploy/ansible
ansible-playbook site.yml --tags app
```

> Faster alternative: build natively on an app VM (it's real x86 — no
> emulation). Install Elixir/Erlang there, `cd testing && MIX_ENV=prod mix
> release`, then pull `_build/prod/rel/testing` back into `ansible/files/`.

## Configure secrets

Edit `group_vars/all.yml` (or better, encrypt with `ansible-vault`):

- `secret_key_base` — `cd testing && mix phx.gen.secret`
- `release_cookie` — any shared random string

## Run

```sh
ansible-playbook site.yml                 # everything
ansible-playbook site.yml --tags app      # just redeploy the app cluster
ansible-playbook site.yml --limit app-1   # one host
ansible-playbook site.yml --check         # dry-run / diff
```

Re-running is idempotent; pushing a new release = drop a fresh
`files/testing-rel.tgz` and `ansible-playbook site.yml --tags app`.

## Verify

```sh
# cluster formed?
ssh root@37.27.20.234 '/opt/livestash/bin/testing remote'   # then Node.list()
# run a load test (from the load VM)
ssh root@46.62.151.189 '/opt/k6/run-k6.sh -e BASE_PATH=/performance/livestash_redis'
```

For 15k+ VUs, `run-k6.sh` targets the load VM private IP (`10.10.0.6:80`) instead
of `127.0.0.1` to avoid loopback ephemeral-port exhaustion. Redeploy with
`--tags load` after changing sysctl or `run-k6.sh`.

Log runs to CSV and generate charts:

```sh
# on load VM — one comparison group (all adapters)
/opt/k6/run_matrix.sh --ttl 60 --vus 1000 --adapter all

# copy log back, export charts
scp -P 2222 root@46.62.151.189:/opt/k6/runs.csv testing/observability/charts/
cd testing/observability/charts && ./generate_charts.sh --group ttl60s-vus1000
```

Grafana: http://37.27.16.253:3000
Prometheus: http://37.27.16.253:9090 (chart export, ad-hoc queries from your laptop)

## What Ansible does NOT do

Build the release — that's the Docker step above. Ansible only ships and starts
the prebuilt artifact.


## After setup

Test cluster

```
ssh -p 2222 root@37.27.20.234 'set -a; source /etc/livestash/app.env; set +a; /opt/livestash/bin/testing rpc "IO.inspect(Node.list())"'
```

Run test
```
ssh -p 2222 root@46.62.151.189
/opt/k6/run-k6.sh -e BASE_PATH=/performance/livestash_ets
```

```
/opt/k6/run-k6.sh \
  -e BASE_PATH=/performance/livestash_redis \
  -e VUS=100 \
  -e TEST_DURATION_SEC=180 \
  -e SIZE_KB=100
  ```
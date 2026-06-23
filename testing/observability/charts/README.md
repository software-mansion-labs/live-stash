Usage

# activate venv

```
python3 -m venv .venv
source .venv/bin/activate
```

# install deps once

```
pip install requests matplotlib pyyaml numpy
```

# copy the example, fill in real timestamps

```
cp runs_example.yaml runs.yaml
```

# generate all charts

```
python export_charts.py runs.yaml --out charts/
```

# or just specific ones, in SVG for a blog

```
python export_charts.py runs.yaml --out charts/ --format svg \
 --metrics k6_first_render_rtt k6_stash_rtt k6_reconnect_rtt
```

# how to check execution time

```
  curl -s 'http://localhost:9090/api/v1/query?query=live_stash_stash_called_total' | python3 -m json.tool
```

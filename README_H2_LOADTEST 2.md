## H2 (Redis Pub/Sub rooms scalability) – Load Test + Analysis

### Status

This repo now includes:
- Redis Pub/Sub adapter support (enabled by `REDIS_URL`)
- k6 script to ramp concurrent rooms to 500
- JSON output analysis script

### 0) Start dependencies (Postgres + Redis) via Docker

From repo root:

```bash
docker compose up -d
docker compose ps
```

### 1) Start backend with Redis Pub/Sub enabled

From `backend/`:

```bash
export REDIS_URL="redis://localhost:6379"
mix ecto.setup
mix phx.server
```

### 2) Install k6 (macOS)

```bash
brew install k6
```

### 3) Run the H2 load test (outputs JSON)

From repo root:

```bash
k6 run --out json=analysis/k6_h2_out.json \
  -e API_BASE="http://127.0.0.1:4000/api" \
  -e WS_BASE="ws://127.0.0.1:4000/socket/websocket" \
  loadtest/k6/h2_rooms.js
```

Success criteria in-script:
- p95 latency <= 300ms (`s2c_question_revealed_latency_ms`)
- error rate < 1% (`h2_errors`)

### 4) Analyze the JSON output

```bash
python3 analysis/h2_k6_analyze.py --in analysis/k6_h2_out.json --outdir analysis/h2_results
```

Outputs:
- `analysis/h2_results/h2_summary.txt`
- `analysis/h2_results/h2_latency_timeseries.png`

### 5) Monitoring during test (macOS-friendly)

You can use:
- **Terminal 2 (Erlang VM)**: open Phoenix dashboard at `http://localhost:4000/dev/dashboard`
- **Terminal 3 (system)**: `top -o cpu`
- **Terminal 4 (redis)**: `docker exec -it vnparty_redis redis-cli info | head`

For the full thesis setup on Linux, use Observer (`:observer.start()` in `iex -S mix phx.server`) and `watch`.


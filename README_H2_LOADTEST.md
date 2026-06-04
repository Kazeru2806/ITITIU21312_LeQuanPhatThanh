# H2 — Scalability (Redis Pub/Sub) load test

## What you are testing

**Hypothesis H2:** With Redis Pub/Sub enabled, the system scales to many concurrent rooms while keeping **p95 server→client question reveal latency ≤ 300 ms** and **error rate < 1%**.

H2 is a **load / scalability** test, not a gameplay UX test.

---

## Important: do not use localhost for thesis results

The old README ran k6 against `127.0.0.1:4000`. That only measures a dev laptop, not your deployed architecture.

For thesis-quality H2 you must target the **same production backend** you deploy (Render + Redis), e.g.:

```bash
export API_BASE="https://YOUR-SERVICE.onrender.com/api"
export WS_BASE="wss://YOUR-SERVICE.onrender.com/socket/websocket"
export REDIS_URL="redis://..."   # must be set on Render, not only locally
```

k6 runs from your Mac or a dedicated load machine; **the server under test is Render**.

---

## Prerequisites

### On Render (backend service)

1. Postgres attached (`DATABASE_URL`)
2. **Redis** attached — set `REDIS_URL` in Render environment variables
3. Redeploy so `Phoenix.PubSub.Redis` starts (see `backend/lib/vn_party/application.ex`)
4. `ALLOWED_ORIGINS` includes your Vercel player + host URLs

Verify Redis is active: check Render logs for PubSub Redis adapter on boot.

### On your Mac

```bash
brew install k6
cd vn-party-thesis/analysis && pip install -r requirements.txt
```

---

## Run k6 against production

```bash
cd vn-party-thesis
k6 run --out json=analysis/k6_h2_out.json \
  -e API_BASE="$API_BASE" \
  -e WS_BASE="$WS_BASE" \
  loadtest/k6/h2_rooms.js
```

Built-in thresholds (in script):

- `s2c_question_revealed_latency_ms` p95 ≤ 300
- `h2_errors` rate < 1%

**Warning:** Ramping to 500 virtual rooms against a small Render plan may fail for **infrastructure** reasons (CPU/RAM/plan limits), not necessarily application logic. Document your Render plan tier in the thesis.

---

## Analyze results

```bash
python analysis/h2_k6_analyze.py \
  --in analysis/k6_h2_out.json \
  --outdir analysis/h2_results
```

Outputs:

- `analysis/h2_results/h2_summary.txt`
- `analysis/h2_results/h2_latency_timeseries.png`

---

## What to report academically

| Item | Why |
|------|-----|
| Render plan + region | Reproducibility |
| `REDIS_URL` enabled (yes/no) | H2 depends on Redis Pub/Sub |
| k6 stages (50→500 VUs) | Load profile |
| p95 latency + error rate | Pass/fail vs thresholds |
| Comparison **without** Redis (optional) | Shows why Pub/Sub was added |

---

## Local / VM (development only)

Use Docker Compose + local k6 only to **debug the script**, not as final thesis numbers:

```bash
docker compose up -d
export REDIS_URL="redis://localhost:6379"
cd backend && mix phx.server
# k6 with 127.0.0.1 — dev smoke test only
```

---

## VM sync

See [README_SYNC_VM.md](README_SYNC_VM.md).

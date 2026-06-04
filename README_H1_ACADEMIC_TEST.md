# H1 — Latency hypothesis (step-by-step)

## What you are testing

**Hypothesis H1:** When the network is moderately degraded, player messages still reach the server quickly enough for gameplay — specifically **p95 latency ≤ 300 ms** for `submit_prediction` in Truth Collapse.

This is **not** a manual “play the game and guess” test. It is a **controlled measurement** using:

1. A load generator (`tools/loadgen/latency_loadgen.mjs`)
2. Rows stored in Postgres (`latency_measurements`)
3. A Python script that computes p50/p95/p99 and draws a CDF

---

## Where to run this (production vs VM)

| Setup | Use when |
|-------|----------|
| **Render backend (production)** | Thesis results that match your deployed demo (Vercel + Render) |
| **Ubuntu VM** | Optional: apply `tc netem` on the VM network interface for artificial delay |

You do **not** need the VM if you test against Render. You **do** need netem (or similar) somewhere on the path if you want to simulate “degraded WAN” — typically on the machine that runs the load generator, or on a Linux VM between client and Render.

**Set these before running loadgen against Render:**

```bash
export API_BASE="https://YOUR-SERVICE.onrender.com/api"
export WS_BASE="wss://YOUR-SERVICE.onrender.com/socket/websocket"
```

---

## Step 0 — One-time setup

On your Mac (or Linux test machine):

```bash
cd vn-party-thesis/tools/loadgen && npm install
python3 -m venv ~/vn-party-venv && source ~/vn-party-venv/bin/activate
pip install -r vn-party-thesis/analysis/requirements.txt
```

Confirm the backend is up:

```bash
curl -s "$API_BASE/health" || curl -s "${API_BASE%/api}/api/health"
```

---

## Step 1 — Baseline (no artificial delay)

**Terminal A:** backend already running on Render (no action).

**Terminal B:** run loadgen:

```bash
cd vn-party-thesis/tools/loadgen
node latency_loadgen.mjs \
  --api "$API_BASE" \
  --ws "$WS_BASE" \
  --players 8 \
  --messages 100 \
  --interval-ms 500 \
  --mode truth_collapse
```

The script prints `room=XXXX`. Copy that code.

---

## Step 2 — Export latency CSV from the server

You need shell access to the environment where Postgres lives (Render shell, or VM):

```bash
cd backend
mix telemetry.export_latency XXXX \
  --event submit_prediction \
  --out ../analysis/out_baseline.csv
```

If you only have Render and no shell, run export locally against the same `DATABASE_URL` (read-only is enough).

---

## Step 3 — Degraded network (moderate scenario)

On a **Linux** machine that can shape traffic toward Render (VM recommended):

```bash
cd vn-party-thesis
export IFACE=eth0   # see: ip route get 1.1.1.1
./scripts/netem/apply.sh moderate
```

Re-run Step 1 (new room), then export to `analysis/out_moderate.csv`, then:

```bash
./scripts/netem/clear.sh
```

Repeat for `light` and `heavy` if your thesis matrix requires four scenarios.

---

## Step 4 — Analysis (thesis statistics)

```bash
source ~/vn-party-venv/bin/activate
python analysis/latency_analyze.py \
  --in analysis/out_moderate.csv \
  --outdir analysis/results \
  --scenario moderate \
  --event submit_prediction
```

Open `analysis/results/latency_report_moderate_submit_prediction.txt`.

---

## Step 5 — Pass / fail

| Result | Meaning |
|--------|---------|
| **p95 ≤ 300 ms** in **moderate** | H1 supported for that scenario |
| **p95 > 300 ms** in heavy | Expected; document as “functional but tail latency grows under stress” |

Report in thesis: **n**, **p50**, **p90**, **p95**, **p99**, scenario name, netem parameters, API/WS URLs used.

---

## Minimum sample size

Default loadgen: **8 players × 100 messages = 800 samples** per scenario.

---

## Checklist before you cite results

- [ ] `VITE_API_URL` / `VITE_WS_URL` on Vercel point to the **same** Render backend you measured
- [ ] Export filtered by `--event submit_prediction`
- [ ] CSV + CDF PNG saved for appendix
- [ ] Scenario documented (baseline / light / moderate / heavy)

---

## VM sync (optional local copy)

See [README_SYNC_VM.md](README_SYNC_VM.md).

# H1 latency — academic test protocol

## Hypothesis (H1)

Under **moderate** simulated WAN impairment, client→server latency for gameplay messages remains acceptable: **p95 ≤ 300 ms** for `submit_prediction` (Truth Collapse load path).

## Why H1 can “fail” under degradation

1. **TCP + netem**: artificial delay/loss inflates tail latency (retransmits), not only app time.
2. **Bursty load**: many players sending at once queues on one VM CPU.
3. **Wrong network interface** for `tc netem` (traffic bypasses the qdisc).
4. **Mixed events** in DB without filtering `submit_prediction`.

This project records one row per message in `latency_measurements` with `event`, `latency_ms`, and timestamps.

## Prerequisites (VM)

```bash
sudo apt-get install -y iproute2
cd ~/vn-party-thesis/backend && mix deps.get && mix ecto.setup
cd ~/vn-party-thesis/tools/loadgen && npm install
python3 -m venv ~/vn-party-venv && source ~/vn-party-venv/bin/activate
pip install -r ~/vn-party-thesis/analysis/requirements.txt
```

Find the interface used to reach the VM (often `eth0` or `enp0s1`):

```bash
ip route get 8.8.8.8
export IFACE=eth0   # replace with your interface name
```

## Controlled procedure (one scenario)

Run **on the VM** where Phoenix listens on `0.0.0.0:4000`.

### A. Baseline (no netem)

```bash
cd ~/vn-party-thesis
./scripts/netem/clear.sh
cd backend && mix phx.server
```

Second terminal:

```bash
cd ~/vn-party-thesis/tools/loadgen
node latency_loadgen.mjs --host 127.0.0.1 --players 8 --messages 100 --interval-ms 500 --mode truth_collapse
```

Note the printed `room=XXXX`.

### B. Export samples

```bash
cd ~/vn-party-thesis/backend
mix telemetry.export_latency ROOMCODE --event submit_prediction --out ../analysis/out_baseline.csv
```

### C. Apply impairment and repeat

```bash
./scripts/netem/apply.sh moderate
# re-run loadgen (new room or same with fresh create)
node tools/loadgen/latency_loadgen.mjs --host 127.0.0.1 --players 8 --messages 100 --interval-ms 500
mix telemetry.export_latency ROOMCODE --event submit_prediction --out ../analysis/out_moderate.csv
./scripts/netem/clear.sh
```

Repeat for `light`, `heavy` if your thesis matrix requires four scenarios.

### D. Analysis (reportable statistics)

```bash
source ~/vn-party-venv/bin/activate
python analysis/latency_analyze.py \
  --in analysis/out_moderate.csv \
  --outdir analysis/results \
  --scenario moderate \
  --event submit_prediction
```

Report in thesis: **n**, **p50**, **p90**, **p95**, **p99**, CDF figure path, scenario parameters from `scripts/netem/`.

### E. Pass criterion

From `analysis/results/latency_report_moderate_submit_prediction.txt`:

- **Pass H1** if `p95 <= 300.00` ms in **moderate**.
- Document that **heavy** may fail p95 while the app remains functional — that supports the “degraded conditions” narrative.

## Minimum sample size (thesis wording)

Per scenario: **8 players × 100 messages = 800 samples** (loadgen default). Four scenarios → **3200** total if all complete.

## Reproducibility checklist

- [ ] Single VM, `mix phx.server` bound to `0.0.0.0:4000`
- [ ] `longpoll: true` on `/socket` (required for loadgen fallback)
- [ ] netem applied on correct `IFACE`
- [ ] Export filtered by `--event submit_prediction`
- [ ] CSV + PNG + report text archived for appendix

## Sync from Mac before testing

See [README_SYNC_VM.md](README_SYNC_VM.md).

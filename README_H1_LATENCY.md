## H1 (Latency Hypothesis) – How to Measure and Prove

### What “finished” means

H1 is finished when you can:
- run the 4 network scenarios (baseline/light/moderate/heavy),
- generate **≥ 3200** latency samples total (8 players × 100 msgs × 4 scenarios),
- compute **p50/p90/p95/p99** and produce **CDF plots**,
- and check whether **p95 ≤ 300ms** in at least the **moderate** scenario.

### What we measure

We record **client→server (C2S)** message latency:

\[
latency\_ms = server\_received\_timestamp\_ms - client\_timestamp\_ms
\]

Every outgoing player message now includes `client_timestamp_ms` automatically.
The server records latency rows in `latency_measurements`.

### 0) Install prerequisites (Ubuntu 22.04)

Network emulation:

```bash
sudo apt-get update
sudo apt-get install -y iproute2
```

Python analysis:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r analysis/requirements.txt
```

Load generator:

```bash
cd tools/loadgen
npm install
```

### 1) Start backend

```bash
cd backend
mix ecto.setup
mix phx.server
```

### 2) Run a scenario and generate samples

Set the interface used for tc (common: `eth0`):

```bash
export IFACE=eth0
```

Apply netem:

```bash
./scripts/netem/apply.sh moderate
```

Run loadgen (8 players × 100 msgs):

```bash
node tools/loadgen/latency_loadgen.mjs --host 127.0.0.1 --players 8 --messages 100
```

Clear netem:

```bash
./scripts/netem/clear.sh
```

Repeat for: `baseline`, `light`, `moderate`, `heavy`.

### 3) Export latency data to CSV

After each scenario run, export to a named CSV:

```bash
cd backend
mix telemetry.export_latency ROOMCODE --event submit_prediction --out ../analysis/out_moderate.csv
```

Alternatively, HTTP export:

`GET /api/telemetry/latency.csv?room_code=ROOMCODE&event=submit_prediction`

### 4) Compute percentiles + generate CDF plots

```bash
python analysis/latency_analyze.py --in analysis/out_moderate.csv --outdir analysis/results --scenario moderate --event submit_prediction
```

Outputs:
- `analysis/results/latency_report_<scenario>_<event>.txt`
- `analysis/results/latency_cdf_<scenario>_<event>.png`
- `analysis/results/latency_hist_<scenario>_<event>.png`

### 5) H1 pass/fail

Open the report file and check:
- `p95: ...`

H1 passes if:
- `p95 <= 300.00` for the **moderate** scenario.


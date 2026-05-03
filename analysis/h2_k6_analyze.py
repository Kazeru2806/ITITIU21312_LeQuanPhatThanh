import argparse
import json
from pathlib import Path

import pandas as pd
import matplotlib.pyplot as plt


def read_k6_json_lines(path: Path):
    rows = []
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if obj.get("type") != "Point":
                continue
            metric = obj.get("metric")
            data = obj.get("data") or {}
            if not metric or "value" not in data:
                continue
            rows.append(
                {
                    "time": data.get("time"),
                    "metric": metric,
                    "value": data.get("value"),
                }
            )
    return pd.DataFrame(rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", required=True, help="k6 --out json=... output file (JSON lines)")
    ap.add_argument("--outdir", required=True)
    args = ap.parse_args()

    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    df = read_k6_json_lines(Path(args.inp))
    if df.empty:
        raise SystemExit("No k6 Point metrics found in JSON output.")

    # Filter our metrics
    lat = df[df["metric"] == "s2c_question_revealed_latency_ms"].copy()
    err = df[df["metric"] == "h2_errors"].copy()

    report_path = outdir / "h2_summary.txt"
    with report_path.open("w", encoding="utf-8") as f:
        if not lat.empty:
            p95 = lat["value"].quantile(0.95)
            p50 = lat["value"].quantile(0.50)
            p90 = lat["value"].quantile(0.90)
            p99 = lat["value"].quantile(0.99)
            f.write(f"latency_samples: {len(lat)}\n")
            f.write(f"p50_ms: {p50:.2f}\n")
            f.write(f"p90_ms: {p90:.2f}\n")
            f.write(f"p95_ms: {p95:.2f}\n")
            f.write(f"p99_ms: {p99:.2f}\n")
        else:
            f.write("latency_samples: 0\n")

        if not err.empty:
            # errors is a Rate metric (0/1 points). Approximate mean as rate.
            rate = err["value"].mean()
            f.write(f"error_rate: {rate:.4f}\n")
        else:
            f.write("error_rate: unknown\n")

    # Plot latency over time (scatter-ish)
    if not lat.empty:
        lat["time"] = pd.to_datetime(lat["time"], errors="coerce")
        lat = lat.dropna(subset=["time"])
        plt.figure(figsize=(9, 4.8))
        plt.plot(lat["time"], lat["value"], ".", markersize=2)
        plt.title("H2: question_revealed S2C latency over time")
        plt.xlabel("time")
        plt.ylabel("latency (ms)")
        plt.grid(True, alpha=0.25)
        out = outdir / "h2_latency_timeseries.png"
        plt.tight_layout()
        plt.savefig(out, dpi=180)

    print(f"Wrote {report_path}")


if __name__ == "__main__":
    main()


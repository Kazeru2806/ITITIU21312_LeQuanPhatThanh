import argparse
import math
from pathlib import Path

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt


def percentiles(ms: np.ndarray, ps=(50, 90, 95, 99)):
    out = {}
    for p in ps:
        out[f"p{p}"] = float(np.percentile(ms, p))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", required=True, help="Input CSV exported from telemetry")
    ap.add_argument("--outdir", required=True, help="Output directory for report + plots")
    ap.add_argument("--scenario", default="unknown", help="Scenario label (baseline/light/moderate/heavy)")
    ap.add_argument("--event", default=None, help="Filter by event (e.g. commit_answer)")
    args = ap.parse_args()

    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    df = pd.read_csv(args.inp)
    df = df[df["latency_ms"].notna()]
    df["latency_ms"] = pd.to_numeric(df["latency_ms"], errors="coerce")
    df = df[df["latency_ms"].notna()]

    if args.event:
        df = df[df["event"] == args.event]

    ms = df["latency_ms"].to_numpy(dtype=float)
    if ms.size == 0:
        raise SystemExit("No latency samples found after filtering.")

    stats = percentiles(ms)
    stats["count"] = int(ms.size)
    stats["mean"] = float(np.mean(ms))
    stats["stdev"] = float(np.std(ms))
    stats["scenario"] = args.scenario
    stats["event"] = args.event or "ALL"

    # Write JSON-ish text report (easy to paste into thesis)
    report_path = outdir / f"latency_report_{args.scenario}_{stats['event']}.txt"
    with report_path.open("w", encoding="utf-8") as f:
        for k in ["scenario", "event", "count", "mean", "stdev", "p50", "p90", "p95", "p99"]:
            f.write(f"{k}: {stats[k]:.2f}\n" if isinstance(stats[k], float) else f"{k}: {stats[k]}\n")

    # CDF plot
    xs = np.sort(ms)
    ys = np.arange(1, xs.size + 1) / xs.size

    plt.figure(figsize=(7.5, 4.8))
    plt.plot(xs, ys, linewidth=2)
    plt.title(f"CDF of end-to-end latency (C2S)\nscenario={args.scenario}, event={stats['event']}, n={xs.size}")
    plt.xlabel("Latency (ms)")
    plt.ylabel("CDF")
    plt.grid(True, alpha=0.3)

    # Mark p95 line
    p95 = stats["p95"]
    plt.axvline(p95, linestyle="--", linewidth=1.5)
    plt.text(p95, 0.05, f"p95={p95:.1f}ms", rotation=90, va="bottom", ha="right")

    cdf_path = outdir / f"latency_cdf_{args.scenario}_{stats['event']}.png"
    plt.tight_layout()
    plt.savefig(cdf_path, dpi=180)

    # Histogram
    plt.figure(figsize=(7.5, 4.8))
    bins = min(80, max(10, int(math.sqrt(xs.size))))
    plt.hist(ms, bins=bins)
    plt.title(f"Latency histogram (C2S)\nscenario={args.scenario}, event={stats['event']}, n={xs.size}")
    plt.xlabel("Latency (ms)")
    plt.ylabel("Count")
    plt.grid(True, alpha=0.3)
    hist_path = outdir / f"latency_hist_{args.scenario}_{stats['event']}.png"
    plt.tight_layout()
    plt.savefig(hist_path, dpi=180)

    print(f"Wrote {report_path}")
    print(f"Wrote {cdf_path}")
    print(f"Wrote {hist_path}")


if __name__ == "__main__":
    main()


#!/usr/bin/env python3
"""Plot inference latency vs JSONL row order (thermal / drift visualization)."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def load_rows(path: Path) -> list[dict]:
    rows: list[dict] = []
    with path.open(encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            rows.append(json.loads(line))
    return rows


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("jsonl", type=Path, help="runner.py output JSONL")
    ap.add_argument(
        "-o",
        "--out",
        type=Path,
        default=Path("latency_vs_run.png"),
        help="Output PNG path",
    )
    ap.add_argument(
        "--title",
        default="Inference latency vs run index (JSONL order)",
        help="Plot title",
    )
    args = ap.parse_args()

    if not args.jsonl.is_file():
        print(f"ERROR: not a file: {args.jsonl}", file=sys.stderr)
        return 1

    try:
        import matplotlib.pyplot as plt
    except ImportError:
        print("ERROR: matplotlib required. pip install -r requirements.txt", file=sys.stderr)
        return 1

    rows = load_rows(args.jsonl)
    if not rows:
        print("ERROR: no rows in JSONL", file=sys.stderr)
        return 1

    x = list(range(len(rows)))
    y = [float(r.get("elapsed_ms", 0) or 0) for r in rows]

    fig, ax = plt.subplots(figsize=(10, 4))
    ax.plot(x, y, marker="o", markersize=2, linewidth=0.8, alpha=0.85)
    ax.set_xlabel("Run index (order in JSONL)")
    ax.set_ylabel("elapsed_ms")
    ax.set_title(args.title)
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    args.out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(args.out, dpi=150)
    print(f"Wrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

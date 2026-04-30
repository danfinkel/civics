"""
Re-score an existing day1 JSONL using current score_field + ground_truth.csv (no inference).

Usage:
  cd /path/to/civics && .venv/bin/python spike/scripts/day1/day1_rescore.py
  .venv/bin/python spike/scripts/day1/day1_rescore.py --in spike/scripts/day1/day1_extraction_results.jsonl
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from day1_extract import DEFAULT_GT, load_ground_truth, score_field

DEFAULT_IN = SCRIPT_DIR / "day1_extraction_results.jsonl"


def main() -> None:
    ap = argparse.ArgumentParser(description="Re-score day1 JSONL without re-running the model")
    ap.add_argument("--in", dest="in_path", type=Path, default=DEFAULT_IN)
    ap.add_argument("--ground-truth", type=Path, default=DEFAULT_GT)
    args = ap.parse_args()

    if not args.in_path.exists():
        raise SystemExit(f"Input JSONL not found: {args.in_path}")
    if not args.ground_truth.exists():
        raise SystemExit(f"Ground truth not found: {args.ground_truth}")

    by_artifact = load_ground_truth(args.ground_truth)
    rows: list[dict] = []
    for line in args.in_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        rows.append(json.loads(line))

    # Last row wins per (artifact_id, variant) for summary (handles appended retries)
    by_key: dict[tuple[str, str], dict] = {}
    for r in rows:
        key = (r["artifact_id"], r.get("variant", ""))
        by_key[key] = r

    # Per-row rescored field_scores + aggregates
    all_scores: list[int] = []
    label_totals: dict[str, int] = defaultdict(int)
    table: dict[str, dict[str, float | None]] = defaultdict(lambda: {"clean": None, "degraded": None})
    flagged: dict[str, dict] = {}

    for key in sorted(by_key.keys(), key=lambda k: (k[0], k[1])):
        aid, variant = key
        r = by_key[key]
        fields = by_artifact.get(aid, {})
        if not fields:
            continue
        if not r.get("parse_ok") or not r.get("parsed"):
            continue

        scores = {}
        for fname, expected in fields.items():
            s = score_field(r["parsed"].get(fname), expected)
            entry = {"score": s["score"], "label": s["label"]}
            if s.get("note"):
                entry["note"] = s["note"]
            scores[fname] = entry
            label_totals[s["label"]] += 1
            all_scores.append(s["score"])

        pts = [x["score"] for x in scores.values()]
        avg = round(sum(pts) / len(pts), 4) if pts else None
        hall = sum(1 for x in scores.values() if x["label"] == "hallucinated")

        table[aid][variant] = avg
        run_label = f"{aid}-{variant}"
        if run_label in ("D02-degraded", "D08-degraded", "D12-degraded"):
            flagged[run_label] = {
                "avg_score": avg,
                "hallucination_count": hall,
                "field_breakdown": {k: v["label"] for k, v in scores.items()},
            }

    n_fields = len(all_scores)
    n_hall = label_totals["hallucinated"]
    halluc_rate = 100.0 * n_hall / n_fields if n_fields else 0.0
    # Point recovery vs perfect 2 per field
    point_accuracy = 100.0 * sum(all_scores) / (2 * n_fields) if n_fields else 0.0
    n_ep = label_totals["exact"] + label_totals["partial"]
    exact_partial_rate = 100.0 * n_ep / n_fields if n_fields else 0.0

    print("=== Re-score (empty string / null => missing, not partial) ===")
    print(f"Input: {args.in_path}")
    print(f"Ground truth: {args.ground_truth}")
    print(f"Unique (artifact, variant) rows scored: {len([k for k in by_key if by_key[k].get('parse_ok') and by_key[k].get('parsed')])}")
    print(f"Total field judgments: {n_fields}")
    print()
    print("Field labels (corrected):")
    for lab in sorted(label_totals.keys(), key=lambda x: -label_totals[x]):
        print(f"  {lab:14} {label_totals[lab]}")
    print()
    print(f"Point recovery (sum(score) / 2N): {point_accuracy:.2f}%")
    print(f"Exact + partial rate:            {exact_partial_rate:.2f}%")
    print(f"Hallucination rate:              {halluc_rate:.2f}%")
    print()

    print("=== Cross-artifact mean score (parse_ok rows only) ===")
    print(f"{'artifact':8} {'clean':>10} {'degraded':>10}")
    for aid in sorted(table.keys(), key=lambda s: (len(s), s)):
        cl = table[aid].get("clean")
        dg = table[aid].get("degraded")
        cls = f"{cl:+.4f}" if isinstance(cl, (int, float)) else "    —"
        dgs = f"{dg:+.4f}" if isinstance(dg, (int, float)) else "    —"
        print(f"{aid:8} {cls:>10} {dgs:>10}")
    print()

    print("=== Flagged: D02-degraded, D08-degraded, D12-degraded (corrected) ===")
    for name in ("D02-degraded", "D08-degraded", "D12-degraded"):
        info = flagged.get(name)
        if not info:
            print(f"{name}: (no parse_ok row in JSONL)")
            continue
        print(f"{name}: avg_score={info['avg_score']}, hallucination_count={info['hallucination_count']}")
        print(f"  per-field labels: {info['field_breakdown']}")


if __name__ == "__main__":
    main()

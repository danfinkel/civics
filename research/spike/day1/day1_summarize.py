"""
Summarize Day 1 JSONL from day1_extract.py.

Usage:
  .venv/bin/python spike/scripts/day1/day1_summarize.py
  .venv/bin/python spike/scripts/day1/day1_summarize.py --in path/to/results.jsonl
  .venv/bin/python spike/scripts/day1/day1_summarize.py --show-parse-fails
"""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_IN = SCRIPT_DIR / "day1_extraction_results.jsonl"


def load_rows(path: Path) -> list[dict]:
    lines = path.read_text(encoding="utf-8").splitlines()
    return [json.loads(l) for l in lines if l.strip()]


def main() -> None:
    ap = argparse.ArgumentParser(description="Summarize day1_extraction_results.jsonl")
    ap.add_argument("--in", dest="in_path", type=Path, default=DEFAULT_IN)
    ap.add_argument(
        "--show-parse-fails",
        action="store_true",
        help="Print truncated raw_response for rows where parse_ok is false",
    )
    args = ap.parse_args()

    path = args.in_path
    if not path.exists():
        raise SystemExit(f"Input not found: {path}")

    rows = load_rows(path)
    if not rows:
        raise SystemExit("No rows in file")

    n = len(rows)
    n_parse = sum(1 for r in rows if r.get("parse_ok"))
    by_variant: dict[str, list[dict]] = defaultdict(list)
    for r in rows:
        by_variant[r.get("variant", "?")].append(r)

    print(f"File: {path}")
    print(f"Records: {n}  |  JSON parse OK: {n_parse}/{n} ({100 * n_parse / n:.1f}%)")
    print()

    label_totals: dict[str, int] = defaultdict(int)
    score_pts: list[int] = []
    for r in rows:
        fs = r.get("field_scores") or {}
        for _fn, d in fs.items():
            label_totals[d.get("label", "?")] += 1
            if isinstance(d.get("score"), int):
                score_pts.append(d["score"])

    print("Field-level labels (across all scored fields):")
    for lab in sorted(label_totals.keys(), key=lambda k: -label_totals[k]):
        print(f"  {lab:14} {label_totals[lab]}")
    if score_pts:
        mean_pt = sum(score_pts) / len(score_pts)
        print(f"Mean score point (2=exact,1=partial,0=unread/miss,-1=halluc): {mean_pt:.3f}  (n={len(score_pts)} fields)")
    print()

    print("By variant (parse OK | mean avg_score | total hallucinations | mean elapsed s):")
    for v in sorted(by_variant.keys()):
        rs = by_variant[v]
        ok = sum(1 for r in rs if r.get("parse_ok"))
        scored = [r for r in rs if r.get("avg_score") is not None]
        mean_avg = sum(r["avg_score"] for r in scored) / len(scored) if scored else float("nan")
        hall = sum(r.get("hallucination_count") or 0 for r in rs)
        mean_s = sum(r.get("elapsed_s") or 0 for r in rs) / len(rs)
        print(f"  {v:8}  parse {ok}/{len(rs)}  avg_score_mean {mean_avg:+.3f}  halluc_count_sum {hall}  elapsed_mean {mean_s:.1f}s")
    print()

    # Table: each run
    print(f"{'artifact':8} {'variant':8} {'parse':5} {'avg_sc':>7} {'hall':>5} {'sec':>6}")
    for r in sorted(rows, key=lambda x: (x["artifact_id"], x.get("variant", ""))):
        aid = r["artifact_id"]
        var = r.get("variant", "")
        po = "yes" if r.get("parse_ok") else "no"
        av = r.get("avg_score")
        avs = f"{av:+.3f}" if isinstance(av, (int, float)) else "—"
        hc = r.get("hallucination_count")
        hcs = str(hc) if hc is not None else "—"
        es = r.get("elapsed_s")
        ess = f"{es:.1f}" if isinstance(es, (int, float)) else "—"
        print(f"{aid:8} {var:8} {po:5} {avs:>7} {hcs:>5} {ess:>6}")

    parse_fails = [r for r in rows if not r.get("parse_ok")]
    if parse_fails:
        print()
        print(f"Parse failures ({len(parse_fails)}): ", end="")
        print(", ".join(f"{r['artifact_id']}-{r.get('variant')}" for r in parse_fails))

    if args.show_parse_fails and parse_fails:
        print()
        print("--- parse_fail raw_response (truncated) ---")
        for r in parse_fails:
            raw = r.get("raw_response") or ""
            tail = raw[:800] + ("…" if len(raw) > 800 else "")
            print(f"\n>> {r['artifact_id']} {r.get('variant')} elapsed={r.get('elapsed_s')}s")
            print(tail if tail.strip() else "(empty raw_response)")

    print()
    print("Tip: re-run only failing or suspect rows, e.g.")
    print("  python spike/scripts/day1/day1_extract.py --artifacts D01,D05,D16 --variants clean,degraded --out spike/scripts/day1/day1_retry.jsonl")


if __name__ == "__main__":
    main()

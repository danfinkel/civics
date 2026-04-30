"""
Merge Day 1 original results with re-run results and produce updated scoring.

Usage:
  cd spike/scripts/day1
  python day1_merge_and_rescore.py

Outputs:
  - day1_merged_results.jsonl: merged results (re-run takes precedence)
  - day1_final_report.txt: updated scoring report
"""

from __future__ import annotations

import json
from pathlib import Path
from collections import defaultdict

SCRIPT_DIR = Path(__file__).resolve().parent

def load_results(path: Path) -> dict[tuple[str, str], dict]:
    """Load results keyed by (artifact_id, variant)."""
    results = {}
    if not path.exists():
        return results
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
                key = (record["artifact_id"], record["variant"])
                results[key] = record
            except (json.JSONDecodeError, KeyError):
                continue
    return results


def main() -> None:
    original_path = SCRIPT_DIR / "day1_extraction_results.jsonl"
    rerun_path = SCRIPT_DIR / "day1_rerun_results.jsonl"
    merged_path = SCRIPT_DIR / "day1_merged_results.jsonl"
    report_path = SCRIPT_DIR / "day1_final_report.txt"

    # Load both result sets
    original = load_results(original_path)
    rerun = load_results(rerun_path)

    # Merge: re-run takes precedence
    merged = dict(original)
    merged.update(rerun)

    # Write merged results
    with open(merged_path, "w", encoding="utf-8") as f:
        for key in sorted(merged.keys()):
            f.write(json.dumps(merged[key], ensure_ascii=False) + "\n")

    print(f"Merged {len(original)} original + {len(rerun)} re-run = {len(merged)} total results")
    print(f"Wrote: {merged_path}")

    # Generate report
    report_lines = [
        "DAY 1 FINAL REPORT (with prompt fixes)",
        "=" * 60,
        "",
        f"Total artifacts tested: {len(merged)}",
        f"  - Original results: {len(original)}",
        f"  - Re-run with fixes: {len(rerun)}",
        "",
    ]

    # Calculate metrics by variant
    by_variant = defaultdict(lambda: {"scores": [], "hallucinations": 0, "parse_ok": 0, "total": 0})

    for record in merged.values():
        variant = record.get("variant", "unknown")
        by_variant[variant]["total"] += 1

        if record.get("parse_ok"):
            by_variant[variant]["parse_ok"] += 1

        if "avg_score" in record and record["avg_score"] is not None:
            by_variant[variant]["scores"].append(record["avg_score"])

        if "hallucination_count" in record:
            by_variant[variant]["hallucinations"] += record["hallucination_count"]

    # Per-variant summary
    report_lines.append("METRICS BY VARIANT")
    report_lines.append("-" * 40)

    for variant in sorted(by_variant.keys()):
        stats = by_variant[variant]
        scores = stats["scores"]

        report_lines.append(f"\n{variant.upper()}:")
        report_lines.append(f"  Total runs: {stats['total']}")
        report_lines.append(f"  Parse OK: {stats['parse_ok']}/{stats['total']} ({100*stats['parse_ok']/stats['total']:.1f}%)")

        if scores:
            avg_score = sum(scores) / len(scores)
            report_lines.append(f"  Mean avg_score: {avg_score:+.3f}")
            report_lines.append(f"  Total hallucinations: {stats['hallucinations']}")

            # Count by score range
            exact = sum(1 for s in scores if s >= 0.8)
            partial = sum(1 for s in scores if 0.3 <= s < 0.8)
            poor = sum(1 for s in scores if s < 0.3)
            report_lines.append(f"  Score distribution: {exact} excellent (≥0.8), {partial} moderate (0.3-0.8), {poor} poor (<0.3)")

    # Per-artifact breakdown
    report_lines.extend([
        "",
        "PER-ARTIFACT BREAKDOWN",
        "-" * 40,
    ])

    for key in sorted(merged.keys()):
        aid, variant = key
        record = merged[key]
        score = record.get("avg_score", "N/A")
        halluc = record.get("hallucination_count", "N/A")
        parse = "OK" if record.get("parse_ok") else "FAIL"
        elapsed = record.get("elapsed_s", "N/A")

        report_lines.append(f"{aid} {variant}: score={score}, halluc={halluc}, parse={parse}, time={elapsed}s")

    # Write report
    report_text = "\n".join(report_lines)
    with open(report_path, "w", encoding="utf-8") as f:
        f.write(report_text)

    print(f"\nReport:")
    print(report_text)
    print(f"\nWrote report to: {report_path}")


if __name__ == "__main__":
    main()

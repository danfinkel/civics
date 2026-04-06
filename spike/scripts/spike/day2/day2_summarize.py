"""
Summarize Day 2 JSONL results from day2_classify.py and day2_map.py.

Usage:
  python day2_summarize.py --classification day2_classification_results.jsonl
  python day2_summarize.py --mapping day2_mapping_results.jsonl
  python day2_summarize.py --classification cls.jsonl --mapping map.jsonl
"""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_CLASSIFICATION = SCRIPT_DIR / "day2_classification_results.jsonl"
DEFAULT_MAPPING = SCRIPT_DIR / "day2_mapping_results.jsonl"


def load_rows(path: Path) -> list[dict]:
    if not path.exists():
        return []
    lines = path.read_text(encoding="utf-8").splitlines()
    return [json.loads(l) for l in lines if l.strip()]


def summarize_classification(rows: list[dict]) -> None:
    if not rows:
        print("No classification results to summarize.")
        return

    print("=" * 60)
    print("CLASSIFICATION SUMMARY")
    print("=" * 60)

    n = len(rows)
    n_parse = sum(1 for r in rows if r.get("parse_ok"))
    print(f"Records: {n}  |  JSON parse OK: {n_parse}/{n} ({100 * n_parse / n:.1f}%)")
    print()

    # Accuracy by variant
    by_variant: dict[str, list[dict]] = defaultdict(list)
    for r in rows:
        by_variant[r.get("variant", "?")].append(r)

    print("Accuracy by variant:")
    for v in sorted(by_variant.keys()):
        rs = by_variant[v]
        scored = [r for r in rs if r.get("score") is not None]
        exact = sum(1 for r in scored if r.get("score_label") == "exact")
        soft = sum(1 for r in scored if r.get("score_label") == "soft_pass")
        total = len(scored)
        accuracy = (exact + soft) / total * 100 if total else 0
        print(f"  {v:10} {exact + soft}/{total} correct ({accuracy:.1f}%) — exact: {exact}, soft: {soft}")
    print()

    # Confidence calibration
    print("Confidence calibration (exact matches by confidence level):")
    by_confidence: dict[str, dict] = defaultdict(lambda: {"total": 0, "correct": 0})
    for r in rows:
        conf = r.get("confidence", "unknown")
        by_confidence[conf]["total"] += 1
        if r.get("score_label") in {"exact", "soft_pass"}:
            by_confidence[conf]["correct"] += 1

    for conf in ["high", "medium", "low", "unknown"]:
        data = by_confidence[conf]
        if data["total"]:
            pct = data["correct"] / data["total"] * 100
            print(f"  {conf:10} {data['correct']}/{data['total']} correct ({pct:.1f}%)")
    print()

    # Per-artifact breakdown
    print("Per-artifact results:")
    by_artifact: dict[str, list[dict]] = defaultdict(list)
    for r in rows:
        by_artifact[r["artifact_id"]].append(r)

    print(f"{'artifact':8} {'variant':8} {'gold':25} {'predicted':25} {'conf':8} {'score':8}")
    print("-" * 90)
    for aid in sorted(by_artifact.keys(), key=lambda s: (len(s), s)):
        for r in sorted(by_artifact[aid], key=lambda x: x.get("variant", "")):
            var = r.get("variant", "")
            gold = r.get("gold_classification", "")[:24]
            pred = (r.get("classification") or "")[:24]
            conf = r.get("confidence") or ""
            score_label = r.get("score_label", "")
            print(f"{aid:8} {var:8} {gold:25} {pred:25} {conf:8} {score_label:8}")
    print()

    # Critical cases
    wrong_high_conf = [
        r
        for r in rows
        if r.get("score_label") == "wrong" and r.get("confidence") == "high"
    ]
    if wrong_high_conf:
        print("CRITICAL: High confidence wrong classifications:")
        for r in wrong_high_conf:
            print(
                f"  {r['artifact_id']} {r['variant']}: predicted '{r.get('classification')}', "
                f"gold '{r.get('gold_classification')}'"
            )
        print()

    # Edge cases to watch
    d08_results = [r for r in rows if r["artifact_id"] == "D08"]
    if d08_results:
        print("D08 (handwritten_letter) edge case:")
        for r in d08_results:
            status = "✓" if r.get("classification") == "handwritten_letter" else "✗"
            print(
                f"  {r['variant']} {status}: predicted '{r.get('classification')}'"
            )
        print()

    d10_results = [r for r in rows if r["artifact_id"] == "D10"]
    if d10_results:
        print("D10 (government_award_letter vs government_notice) edge case:")
        for r in d10_results:
            correct = r.get("classification") == "government_award_letter"
            status = "✓" if correct else "✗"
            print(
                f"  {r['variant']} {status}: predicted '{r.get('classification')}'"
            )
        print()

    d16_results = [r for r in rows if r["artifact_id"] == "D16"]
    if d16_results:
        print("D16 (Spanish utility bill) edge case:")
        for r in d16_results:
            conf_ok = r.get("confidence") in {"high", "medium"}
            status = "✓" if conf_ok else "⚠"
            print(
                f"  {r['variant']} {status}: predicted '{r.get('classification')}' "
                f"with confidence '{r.get('confidence')}'"
            )
        print()

    # Overall accuracy
    scored = [r for r in rows if r.get("score") is not None]
    exact = sum(1 for r in scored if r.get("score_label") == "exact")
    soft = sum(1 for r in scored if r.get("score_label") == "soft_pass")
    total = len(scored)
    accuracy = (exact + soft) / total * 100 if total else 0
    print(f"OVERALL CLASSIFICATION ACCURACY: {accuracy:.1f}% ({exact + soft}/{total})")
    print(f"  Target: ≥75%")
    print()


def summarize_mapping(rows: list[dict]) -> None:
    if not rows:
        print("No mapping results to summarize.")
        return

    print("=" * 60)
    print("CATEGORY MAPPING SUMMARY")
    print("=" * 60)

    n = len(rows)
    n_parse = sum(1 for r in rows if r.get("parse_ok"))
    print(f"Records: {n}  |  JSON parse OK: {n_parse}/{n} ({100 * n_parse / n:.1f}%)")
    print()

    # Accuracy by variant
    by_variant: dict[str, list[dict]] = defaultdict(list)
    for r in rows:
        by_variant[r.get("variant", "?")].append(r)

    print("Accuracy by variant:")
    for v in sorted(by_variant.keys()):
        rs = by_variant[v]
        scored = [r for r in rs if r.get("score") is not None]
        exact = sum(1 for r in scored if r.get("score_label") == "exact")
        partial = sum(1 for r in scored if r.get("score_label") == "partial")
        total = len(scored)
        # Count partial as 0.5 for scoring purposes
        weighted = exact + (partial * 0.5)
        accuracy = weighted / total * 100 if total else 0
        print(
            f"  {v:10} weighted {weighted:.1f}/{total} ({accuracy:.1f}%) — exact: {exact}, partial: {partial}"
        )
    print()

    # False positive analysis
    false_positives = [
        r
        for r in rows
        if r.get("score_label") == "hallucinated"
        and r.get("gold_assessment") in {"likely_does_not_satisfy", "invalid_proof"}
    ]
    print(f"False positives (accepted when should reject): {len(false_positives)}")
    for r in false_positives:
        print(
            f"  {r['artifact_id']} {r['variant']}: predicted '{r.get('assessment')}', "
            f"gold '{r.get('gold_assessment')}'"
        )
    print()

    # Abstention rate
    abstentions = [r for r in rows if r.get("assessment") == "insufficient_information"]
    if abstentions:
        pct = len(abstentions) / len(rows) * 100
        print(f"Abstention rate: {len(abstentions)}/{len(rows)} ({pct:.1f}%)")
        print()

    # Critical flags
    critical = [r for r in rows if r.get("critical_flags")]
    if critical:
        print("CRITICAL FLAGS:")
        for r in critical:
            for flag in r.get("critical_flags", []):
                print(f"  {r['artifact_id']} {r['variant']}: {flag}")
        print()

    # Per-artifact breakdown
    print("Per-artifact results:")
    by_artifact: dict[str, list[dict]] = defaultdict(list)
    for r in rows:
        by_artifact[r["artifact_id"]].append(r)

    print(f"{'artifact':8} {'variant':8} {'gold':30} {'predicted':30} {'conf':8} {'score':8}")
    print("-" * 100)
    for aid in sorted(by_artifact.keys(), key=lambda s: (len(s), s)):
        for r in sorted(by_artifact[aid], key=lambda x: x.get("variant", "")):
            var = r.get("variant", "")
            gold = r.get("gold_assessment", "")[:29]
            pred = (r.get("assessment") or "")[:29]
            conf = r.get("confidence") or ""
            score_label = r.get("score_label", "")
            crit = " [!]" if r.get("critical_flags") else ""
            print(f"{aid:8} {var:8} {gold:30} {pred:30} {conf:8} {score_label:8}{crit}")
    print()

    # Confidence calibration
    print("Confidence calibration (exact matches by confidence level):")
    by_confidence: dict[str, dict] = defaultdict(lambda: {"total": 0, "correct": 0})
    for r in rows:
        conf = r.get("confidence", "unknown")
        by_confidence[conf]["total"] += 1
        if r.get("score_label") == "exact":
            by_confidence[conf]["correct"] += 1

    for conf in ["high", "medium", "low", "unknown"]:
        data = by_confidence[conf]
        if data["total"]:
            pct = data["correct"] / data["total"] * 100
            print(f"  {conf:10} {data['correct']}/{data['total']} exact ({pct:.1f}%)")
    print()

    # Overall accuracy
    scored = [r for r in rows if r.get("score") is not None]
    exact = sum(1 for r in scored if r.get("score_label") == "exact")
    partial = sum(1 for r in scored if r.get("score_label") == "partial")
    total = len(scored)
    # Count partial as 0.5 for scoring purposes
    weighted = exact + (partial * 0.5)
    accuracy = weighted / total * 100 if total else 0
    print(f"OVERALL MAPPING ACCURACY: {accuracy:.1f}% (weighted: {weighted:.1f}/{total})")
    print(f"  Exact: {exact}, Partial: {partial}")
    print(f"  Target: ≥70%")
    print()

    # Acceptance criteria check
    print("ACCEPTANCE CRITERIA:")
    print(f"  Classification accuracy ≥75%: {'PASS' if accuracy >= 70 else 'FAIL'} (mapping)")

    # Check critical cases
    d08_fail = any(
        r.get("assessment") not in {"invalid_proof", "likely_does_not_satisfy"}
        for r in rows
        if r["artifact_id"] == "D08"
    )
    d10_fail = any(
        r.get("assessment") == "likely_satisfies"
        for r in rows
        if r["artifact_id"] == "D10"
    )
    d07_fail = any(
        r.get("assessment") == "likely_satisfies" and r.get("confidence") == "high"
        for r in rows
        if r["artifact_id"] == "D07"
    )
    d14_fail = any(
        r.get("assessment") != "same_residency_category_duplicate"
        for r in rows
        if r["artifact_id"] == "D14"
    )

    print(f"  D08 (handwritten rejected): {'PASS' if not d08_fail else 'FAIL'}")
    print(f"  D10 (award letter ≠ earned income): {'PASS' if not d10_fail else 'FAIL'}")
    print(f"  D07 (not overconfident on phone bill): {'PASS' if not d07_fail else 'FAIL'}")
    print(f"  D14 (detect duplicate category): {'PASS' if not d14_fail else 'FAIL'}")
    print()


def main() -> None:
    ap = argparse.ArgumentParser(description="Summarize Day 2 results")
    ap.add_argument(
        "--classification",
        type=Path,
        default=DEFAULT_CLASSIFICATION,
        help="Path to classification results JSONL",
    )
    ap.add_argument(
        "--mapping",
        type=Path,
        default=DEFAULT_MAPPING,
        help="Path to mapping results JSONL",
    )
    ap.add_argument(
        "--show-parse-fails",
        action="store_true",
        help="Print raw responses for parse failures",
    )
    args = ap.parse_args()

    cls_rows = load_rows(args.classification)
    map_rows = load_rows(args.mapping)

    if cls_rows:
        summarize_classification(cls_rows)

    if map_rows:
        if cls_rows:
            print("\n")
        summarize_mapping(map_rows)

    if not cls_rows and not map_rows:
        print("No results found. Run day2_classify.py and/or day2_map.py first.")
        print()
        print("Examples:")
        print("  python day2_classify.py")
        print("  python day2_map.py")
        print("  python day2_summarize.py")


if __name__ == "__main__":
    main()

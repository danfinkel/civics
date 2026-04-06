"""
Day 3 Track B Summary — Analyze results and produce acceptance report.

Example:
  python day3_track_b_summarize.py day3_track_b_results.jsonl
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path


def load_results(path: Path) -> list[dict]:
    """Load JSONL results."""
    results = []
    with path.open(encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                results.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return results


def analyze_results(results: list[dict]) -> dict:
    """Analyze results and compute metrics."""
    metrics = {
        "total_runs": len(results),
        "parse_ok": 0,
        "parse_fail": 0,
        "skipped": 0,
        "requirement_status_accuracy": {"exact": 0, "partial": 0, "wrong": 0, "missing": 0, "total": 0},
        "matched_document_accuracy": {"exact": 0, "partial": 0, "wrong": 0, "missing": 0, "total": 0},
        "missing_item_detection": {"correct": 0, "total": 0},  # B2, B8
        "duplicate_category_detection": {"correct": 0, "total": 0},  # B4
        "abstention_accuracy": {"correct": 0, "total": 0},  # B7
        "critical_flags": [],
        "by_scenario": defaultdict(lambda: defaultdict(int)),
    }

    for r in results:
        if r.get("skipped"):
            metrics["skipped"] += 1
            continue

        if r.get("parse_ok"):
            metrics["parse_ok"] += 1
        else:
            metrics["parse_fail"] += 1
            continue

        scenario_id = r.get("scenario_id", "unknown")
        scores = r.get("scores", {})
        critical_flags = r.get("critical_flags", [])

        metrics["critical_flags"].extend(critical_flags)

        # Requirement status scores
        for req in scores.get("requirements", []):
            metrics["requirement_status_accuracy"]["total"] += 1
            label = req.get("status_label", "missing")
            if label in metrics["requirement_status_accuracy"]:
                metrics["requirement_status_accuracy"][label] += 1

            metrics["matched_document_accuracy"]["total"] += 1
            doc_label = req.get("document_label", "missing")
            if doc_label in metrics["matched_document_accuracy"]:
                metrics["matched_document_accuracy"][doc_label] += 1

        # Missing item detection (B2, B8)
        if scenario_id in ("B2", "B8"):
            metrics["missing_item_detection"]["total"] += 1
            if scores.get("missing_item_detected"):
                metrics["missing_item_detection"]["correct"] += 1
                metrics["by_scenario"][scenario_id]["missing_detected"] += 1

        # Duplicate category detection (B4)
        if scenario_id == "B4":
            metrics["duplicate_category_detection"]["total"] += 1
            if scores.get("duplicate_flag_correct"):
                metrics["duplicate_category_detection"]["correct"] += 1
                metrics["by_scenario"][scenario_id]["duplicate_detected"] += 1

        # Abstention accuracy (B7)
        if scenario_id == "B7":
            metrics["abstention_accuracy"]["total"] += 1
            if scores.get("abstention_correct"):
                metrics["abstention_accuracy"]["correct"] += 1
                metrics["by_scenario"][scenario_id]["abstention_correct"] += 1

    return metrics


def compute_percentages(metrics: dict) -> dict:
    """Compute percentage metrics."""
    pct = {}

    # Requirement status accuracy
    total = metrics["requirement_status_accuracy"]["total"]
    if total > 0:
        exact = metrics["requirement_status_accuracy"]["exact"]
        partial = metrics["requirement_status_accuracy"]["partial"]
        # Count exact as 100%, partial as 50%
        pct["requirement_status_accuracy"] = (exact + 0.5 * partial) / total * 100

    # Matched document accuracy
    total = metrics["matched_document_accuracy"]["total"]
    if total > 0:
        exact = metrics["matched_document_accuracy"]["exact"]
        partial = metrics["matched_document_accuracy"]["partial"]
        pct["matched_document_accuracy"] = (exact + 0.5 * partial) / total * 100

    # Missing item detection recall
    total = metrics["missing_item_detection"]["total"]
    if total > 0:
        pct["missing_item_recall"] = metrics["missing_item_detection"]["correct"] / total * 100

    # Duplicate category detection
    total = metrics["duplicate_category_detection"]["total"]
    if total > 0:
        pct["duplicate_detection"] = metrics["duplicate_category_detection"]["correct"] / total * 100

    # Abstention accuracy
    total = metrics["abstention_accuracy"]["total"]
    if total > 0:
        pct["abstention_accuracy"] = metrics["abstention_accuracy"]["correct"] / total * 100

    return pct


def print_report(metrics: dict, percentages: dict):
    """Print formatted report."""
    print("=" * 60)
    print("DAY 3 TRACK B — BPS PACKET CHECKER RESULTS")
    print("=" * 60)

    print(f"\nTotal runs: {metrics['total_runs']}")
    print(f"  Parse OK: {metrics['parse_ok']}")
    print(f"  Parse fail: {metrics['parse_fail']}")
    print(f"  Skipped: {metrics['skipped']}")

    print("\n" + "-" * 40)
    print("REQUIREMENT STATUS ACCURACY")
    print("-" * 40)
    rsa = metrics["requirement_status_accuracy"]
    print(f"  Exact matches: {rsa['exact']} / {rsa['total']}")
    print(f"  Partial matches: {rsa['partial']} / {rsa['total']}")
    print(f"  Wrong: {rsa['wrong']} / {rsa['total']}")
    print(f"  Missing: {rsa['missing']} / {rsa['total']}")
    if "requirement_status_accuracy" in percentages:
        print(f"  Weighted accuracy: {percentages['requirement_status_accuracy']:.1f}%")
    print(f"  Target: ≥70%")

    print("\n" + "-" * 40)
    print("MATCHED DOCUMENT ACCURACY")
    print("-" * 40)
    mda = metrics["matched_document_accuracy"]
    print(f"  Exact matches: {mda['exact']} / {mda['total']}")
    print(f"  Partial matches: {mda['partial']} / {mda['total']}")
    if "matched_document_accuracy" in percentages:
        print(f"  Weighted accuracy: {percentages['matched_document_accuracy']:.1f}%")

    print("\n" + "-" * 40)
    print("MISSING ITEM DETECTION (B2, B8)")
    print("-" * 40)
    mid = metrics["missing_item_detection"]
    print(f"  Correctly detected: {mid['correct']} / {mid['total']}")
    if "missing_item_recall" in percentages:
        print(f"  Recall: {percentages['missing_item_recall']:.1f}%")
    print(f"  Target: ≥80%")

    print("\n" + "-" * 40)
    print("DUPLICATE CATEGORY DETECTION (B4)")
    print("-" * 40)
    dcd = metrics["duplicate_category_detection"]
    print(f"  Correctly detected: {dcd['correct']} / {dcd['total']}")
    if "duplicate_detection" in percentages:
        print(f"  Pass rate: {percentages['duplicate_detection']:.1f}%")
    print(f"  Target: Pass (hard requirement)")

    print("\n" + "-" * 40)
    print("ABSTENTION ACCURACY (B7)")
    print("-" * 40)
    aa = metrics["abstention_accuracy"]
    print(f"  Correctly abstained: {aa['correct']} / {aa['total']}")
    if "abstention_accuracy" in percentages:
        print(f"  Accuracy: {percentages['abstention_accuracy']:.1f}%")
    print(f"  Target: Pass (phone bill must be questionable)")

    print("\n" + "-" * 40)
    print("CRITICAL FLAGS")
    print("-" * 40)
    if metrics["critical_flags"]:
        for flag in set(metrics["critical_flags"]):
            print(f"  ! {flag}")
    else:
        print("  None")

    print("\n" + "-" * 40)
    print("ACCEPTANCE CRITERIA SUMMARY")
    print("-" * 40)

    checks = [
        ("Requirement status accuracy ≥70%", percentages.get("requirement_status_accuracy", 0) >= 70),
        ("Missing item detection recall ≥80%", percentages.get("missing_item_recall", 0) >= 80),
        ("Duplicate category detection (B4) pass", metrics["duplicate_category_detection"]["correct"] > 0 or metrics["duplicate_category_detection"]["total"] == 0),
        ("Abstention on ambiguous docs (B7) pass", metrics["abstention_accuracy"]["correct"] > 0 or metrics["abstention_accuracy"]["total"] == 0),
        ("Critical false positives = 0", len([f for f in metrics["critical_flags"] if "CRITICAL" in f]) == 0),
    ]

    for criterion, passed in checks:
        status = "✓ PASS" if passed else "✗ FAIL"
        print(f"  {status}: {criterion}")

    all_passed = all(p for _, p in checks)
    print("\n" + "=" * 60)
    if all_passed:
        print("OVERALL: ALL ACCEPTANCE CRITERIA MET")
    else:
        print("OVERALL: SOME CRITERIA NOT MET")
    print("=" * 60)


def main():
    ap = argparse.ArgumentParser(description="Day 3 Track B Summary")
    ap.add_argument("results_file", type=Path, help="Path to day3_track_b_results.jsonl")
    args = ap.parse_args()

    if not args.results_file.exists():
        print(f"Results file not found: {args.results_file}", file=sys.stderr)
        sys.exit(1)

    results = load_results(args.results_file)
    if not results:
        print("No results found in file", file=sys.stderr)
        sys.exit(1)

    metrics = analyze_results(results)
    percentages = compute_percentages(metrics)
    print_report(metrics, percentages)


if __name__ == "__main__":
    main()

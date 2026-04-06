"""
Day 3 Summary Script — Combine Track A and Track B results

Generates a summary report with acceptance criteria scoring and critical flags.

Usage:
    cd spike/scripts/day3
    python day3_summarize.py
    python day3_summarize.py --track-a day3_track_a_results.jsonl --track-b day3_track_b_results.jsonl
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent


def load_jsonl(path: Path) -> list[dict]:
    """Load JSONL file."""
    results = []
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                results.append(json.loads(line))
    return results


def calculate_track_a_metrics(results: list[dict]) -> dict[str, Any]:
    """Calculate Track A acceptance criteria metrics."""
    metrics = {
        "notice_category_accuracy": {"total": 0, "correct": 0, "score_sum": 0},
        "deadline_accuracy": {"total": 0, "correct": 0, "score_sum": 0},
        "proof_pack_accuracy": {"total": 0, "correct": 0, "score_sum": 0},
        "missing_item_recall": {"total": 0, "detected": 0},
        "abstention_accuracy": {"total": 0, "correct": 0},
        "critical_flags": []
    }

    for r in results:
        sid = r.get("scenario_id", "")
        scores = r.get("scores", {})

        # Collect critical flags
        if r.get("critical_flags"):
            metrics["critical_flags"].extend(r["critical_flags"])

        # Notice category extraction (A1-A5, A7, A8 - not A6)
        if sid in ["A1", "A2", "A3", "A4", "A5", "A7", "A8"]:
            if "notice_categories" in scores:
                metrics["notice_category_accuracy"]["total"] += 1
                cat_score = scores["notice_categories"]
                metrics["notice_category_accuracy"]["score_sum"] += cat_score.get("score", 0)
                if cat_score.get("label") in ["exact", "partial"]:
                    metrics["notice_category_accuracy"]["correct"] += 1

        # Deadline extraction
        if sid in ["A1", "A2", "A3", "A4", "A5", "A7", "A8"]:
            if "deadline" in scores:
                metrics["deadline_accuracy"]["total"] += 1
                deadline_score = scores["deadline"]
                metrics["deadline_accuracy"]["score_sum"] += deadline_score.get("score", 0)
                if deadline_score.get("label") in ["exact", "partial"]:
                    metrics["deadline_accuracy"]["correct"] += 1

        # Proof pack assessment accuracy
        if "proof_pack_assessments" in scores:
            for entry in scores["proof_pack_assessments"]:
                metrics["proof_pack_accuracy"]["total"] += 1
                assessment = entry.get("assessment", {})
                metrics["proof_pack_accuracy"]["score_sum"] += assessment.get("score", 0)
                if assessment.get("label") in ["exact", "right_valence"]:
                    metrics["proof_pack_accuracy"]["correct"] += 1

        # Missing item detection (A2, A4, A5)
        if sid in ["A2", "A4", "A5"]:
            metrics["missing_item_recall"]["total"] += 1
            if scores.get("missing_item_detected"):
                metrics["missing_item_recall"]["detected"] += 1

        # Abstention on blurry notice (A6)
        if sid == "A6":
            metrics["abstention_accuracy"]["total"] += 1
            if scores.get("abstention_correct"):
                metrics["abstention_accuracy"]["correct"] += 1

    return metrics


def calculate_track_b_metrics(results: list[dict]) -> dict[str, Any]:
    """Calculate Track B acceptance criteria metrics."""
    metrics = {
        "requirement_status_accuracy": {"total": 0, "correct": 0, "score_sum": 0},
        "missing_item_recall": {"total": 0, "detected": 0},
        "duplicate_detection": {"total": 0, "correct": 0},
        "abstention_accuracy": {"total": 0, "correct": 0},
        "critical_flags": []
    }

    for r in results:
        sid = r.get("scenario_id", "")
        scores = r.get("scores", {})

        # Collect critical flags
        if r.get("critical_flags"):
            metrics["critical_flags"].extend(r["critical_flags"])

        # Requirement status accuracy
        if "requirements" in scores:
            for req in scores["requirements"]:
                metrics["requirement_status_accuracy"]["total"] += 1
                status_score = req.get("status_score", 0)
                metrics["requirement_status_accuracy"]["score_sum"] += status_score
                if status_score > 0:
                    metrics["requirement_status_accuracy"]["correct"] += 1

        # Missing item detection (B2, B3, B8)
        if sid in ["B2", "B3", "B8"]:
            metrics["missing_item_recall"]["total"] += 1
            if scores.get("missing_item_detected"):
                metrics["missing_item_recall"]["detected"] += 1

        # Duplicate category detection (B4)
        if sid == "B4":
            metrics["duplicate_detection"]["total"] += 1
            if scores.get("duplicate_flag_correct"):
                metrics["duplicate_detection"]["correct"] += 1

        # Abstention on ambiguous docs (B7)
        if sid == "B7":
            metrics["abstention_accuracy"]["total"] += 1
            if scores.get("abstention_correct"):
                metrics["abstention_accuracy"]["correct"] += 1

    return metrics


def format_percentage(numerator: int, denominator: int) -> str:
    """Format as percentage."""
    if denominator == 0:
        return "N/A"
    return f"{numerator / denominator * 100:.1f}%"


def format_track_a_report(metrics: dict[str, Any]) -> str:
    """Format Track A metrics as a report."""
    lines = []
    lines.append("=" * 60)
    lines.append("TRACK A — SNAP Proof-Pack Builder")
    lines.append("=" * 60)

    # Notice category extraction accuracy
    cat = metrics["notice_category_accuracy"]
    cat_pct = format_percentage(cat["correct"], cat["total"])
    cat_avg = cat["score_sum"] / max(cat["total"], 1)
    lines.append(f"\nNotice Category Extraction Accuracy:")
    lines.append(f"  Correct: {cat['correct']}/{cat['total']} ({cat_pct})")
    lines.append(f"  Average Score: {cat_avg:.2f} (target: ≥85%)")
    lines.append(f"  Status: {'✓ PASS' if cat['correct'] / max(cat['total'], 1) >= 0.85 else '✗ FAIL'}")

    # Deadline extraction accuracy
    deadline = metrics["deadline_accuracy"]
    deadline_pct = format_percentage(deadline["correct"], deadline["total"])
    deadline_avg = deadline["score_sum"] / max(deadline["total"], 1)
    lines.append(f"\nDeadline Extraction Accuracy:")
    lines.append(f"  Correct: {deadline['correct']}/{deadline['total']} ({deadline_pct})")
    lines.append(f"  Average Score: {deadline_avg:.2f} (target: ≥85%)")
    lines.append(f"  Status: {'✓ PASS' if deadline['correct'] / max(deadline['total'], 1) >= 0.85 else '✗ FAIL'}")

    # Proof pack assessment accuracy
    pp = metrics["proof_pack_accuracy"]
    pp_pct = format_percentage(pp["correct"], pp["total"])
    # Score range: -1 (wrong) to 2 (exact), so normalize to 0-100%
    # Map: -1->0%, 0->33%, 1->67%, 2->100%
    pp_avg = (pp["score_sum"] / max(pp["total"], 1) + 1) / 3 * 100
    lines.append(f"\nProof-Pack Assessment Accuracy:")
    lines.append(f"  Correct: {pp['correct']}/{pp['total']} ({pp_pct})")
    lines.append(f"  Normalized Score: {pp_avg:.1f}% (target: ≥70%)")
    lines.append(f"  Status: {'✓ PASS' if pp_avg >= 70 else '✗ FAIL'}")

    # Missing item detection recall
    missing = metrics["missing_item_recall"]
    missing_pct = format_percentage(missing["detected"], missing["total"])
    lines.append(f"\nMissing-Item Detection Recall:")
    lines.append(f"  Detected: {missing['detected']}/{missing['total']} ({missing_pct})")
    lines.append(f"  Status: {'✓ PASS' if missing['detected'] / max(missing['total'], 1) >= 0.80 else '✗ FAIL'}")

    # Abstention accuracy
    abstain = metrics["abstention_accuracy"]
    if abstain["total"] > 0:
        abstain_pct = format_percentage(abstain["correct"], abstain["total"])
        lines.append(f"\nAbstention on Blurry Notice (A6):")
        lines.append(f"  Correct: {abstain['correct']}/{abstain['total']} ({abstain_pct})")
        lines.append(f"  Status: {'✓ PASS' if abstain['correct'] == abstain['total'] else '✗ FAIL'}")

    # Critical flags
    if metrics["critical_flags"]:
        lines.append(f"\n⚠️  CRITICAL FLAGS:")
        for flag in metrics["critical_flags"]:
            lines.append(f"  - {flag}")
    else:
        lines.append(f"\n✓ No critical flags")

    return "\n".join(lines)


def format_track_b_report(metrics: dict[str, Any]) -> str:
    """Format Track B metrics as a report."""
    lines = []
    lines.append("=" * 60)
    lines.append("TRACK B — BPS Packet Checker")
    lines.append("=" * 60)

    # Requirement status accuracy
    req = metrics["requirement_status_accuracy"]
    req_pct = format_percentage(req["correct"], req["total"])
    # Score range: -1 (wrong) to 2 (exact), so normalize to 0-100%
    # Map: -1->0%, 0->33%, 1->67%, 2->100%
    req_avg = (req["score_sum"] / max(req["total"], 1) + 1) / 3 * 100
    lines.append(f"\nRequirement Status Accuracy:")
    lines.append(f"  Correct: {req['correct']}/{req['total']} ({req_pct})")
    lines.append(f"  Normalized Score: {req_avg:.1f}% (target: ≥70%)")
    lines.append(f"  Status: {'✓ PASS' if req_avg >= 70 else '✗ FAIL'}")

    # Missing item detection recall
    missing = metrics["missing_item_recall"]
    missing_pct = format_percentage(missing["detected"], missing["total"])
    lines.append(f"\nMissing-Item Detection Recall:")
    lines.append(f"  Detected: {missing['detected']}/{missing['total']} ({missing_pct})")
    lines.append(f"  Status: {'✓ PASS' if missing['detected'] / max(missing['total'], 1) >= 0.80 else '✗ FAIL'}")

    # Duplicate category detection
    dup = metrics["duplicate_detection"]
    if dup["total"] > 0:
        dup_pct = format_percentage(dup["correct"], dup["total"])
        lines.append(f"\nDuplicate Category Detection (B4):")
        lines.append(f"  Correct: {dup['correct']}/{dup['total']} ({dup_pct})")
        lines.append(f"  Status: {'✓ PASS' if dup['correct'] == dup['total'] else '✗ FAIL'} (hard requirement)")

    # Abstention accuracy
    abstain = metrics["abstention_accuracy"]
    if abstain["total"] > 0:
        abstain_pct = format_percentage(abstain["correct"], abstain["total"])
        lines.append(f"\nAbstention on Ambiguous Docs (B7):")
        lines.append(f"  Correct: {abstain['correct']}/{abstain['total']} ({abstain_pct})")
        lines.append(f"  Status: {'✓ PASS' if abstain['correct'] == abstain['total'] else '✗ FAIL'}")

    # Critical flags
    if metrics["critical_flags"]:
        lines.append(f"\n⚠️  CRITICAL FLAGS:")
        for flag in metrics["critical_flags"]:
            lines.append(f"  - {flag}")
    else:
        lines.append(f"\n✓ No critical flags")

    return "\n".join(lines)


def format_combined_report(track_a_metrics: dict, track_b_metrics: dict) -> str:
    """Format combined report for Day 5 scoring table."""
    lines = []
    lines.append("=" * 60)
    lines.append("DAY 3 COMBINED SUMMARY — Day 5 Scoring Table")
    lines.append("=" * 60)

    lines.append("\n| Metric | Track A | Track B | Target |")
    lines.append("|--------|---------|---------|--------|")

    # Missing-item detection recall
    a_missing = track_a_metrics["missing_item_recall"]
    b_missing = track_b_metrics["missing_item_recall"]
    a_missing_pct = a_missing["detected"] / max(a_missing["total"], 1) * 100
    b_missing_pct = b_missing["detected"] / max(b_missing["total"], 1) * 100
    lines.append(f"| Missing-item detection recall | {a_missing_pct:.0f}% | {b_missing_pct:.0f}% | ≥80% |")

    # Requirement mapping accuracy (Track A proof pack / Track B requirements)
    # Score range: -1 to 2, normalize to 0-100%
    a_pp = track_a_metrics["proof_pack_accuracy"]
    a_pp_pct = (a_pp["score_sum"] / max(a_pp["total"], 1) + 1) / 3 * 100
    b_req = track_b_metrics["requirement_status_accuracy"]
    b_req_pct = (b_req["score_sum"] / max(b_req["total"], 1) + 1) / 3 * 100
    lines.append(f"| Requirement mapping accuracy | {a_pp_pct:.0f}% | {b_req_pct:.0f}% | ≥70% |")

    # Abstention on ambiguous inputs
    a_abstain = track_a_metrics["abstention_accuracy"]
    b_abstain = track_b_metrics["abstention_accuracy"]
    a_abstain_val = "Pass" if a_abstain["correct"] == a_abstain["total"] else "Fail"
    b_abstain_val = "Pass" if b_abstain["correct"] == b_abstain["total"] else "Fail"
    lines.append(f"| Abstention on ambiguous inputs | {a_abstain_val} | {b_abstain_val} | ≥80% |")

    # Action/deadline extraction (Track A only)
    deadline = track_a_metrics["deadline_accuracy"]
    deadline_pct = deadline["correct"] / max(deadline["total"], 1) * 100
    lines.append(f"| Action/deadline extraction | {deadline_pct:.0f}% | N/A | ≥85% |")

    # Critical false positives
    a_critical = len(track_a_metrics["critical_flags"])
    b_critical = len(track_b_metrics["critical_flags"])
    lines.append(f"| Critical false positives | {a_critical} | {b_critical} | 0 |")

    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description="Day 3 Summary — Combine Track A and Track B results")
    ap.add_argument("--track-a", type=Path, default=SCRIPT_DIR / "day3_track_a_results.jsonl")
    ap.add_argument("--track-b", type=Path, default=SCRIPT_DIR / "day3_track_b_results.jsonl")
    ap.add_argument("--out", type=Path, default=SCRIPT_DIR / "day3_summary.txt")
    ap.add_argument("--track-a-only", action="store_true", help="Only process Track A")
    ap.add_argument("--track-b-only", action="store_true", help="Only process Track B")
    args = ap.parse_args()

    reports = []

    # Process Track A
    if not args.track_b_only:
        if args.track_a.exists():
            track_a_results = load_jsonl(args.track_a)
            track_a_metrics = calculate_track_a_metrics(track_a_results)
            track_a_report = format_track_a_report(track_a_metrics)
            reports.append(track_a_report)
            print(track_a_report)
        else:
            print(f"Track A results not found: {args.track_a}", file=sys.stderr)

    # Process Track B
    if not args.track_a_only:
        if args.track_b.exists():
            track_b_results = load_jsonl(args.track_b)
            track_b_metrics = calculate_track_b_metrics(track_b_results)
            track_b_report = format_track_b_report(track_b_metrics)
            reports.append(track_b_report)
            print(track_b_report)
        else:
            print(f"Track B results not found: {args.track_b}", file=sys.stderr)

    # Combined report (only if both tracks available)
    if not args.track_a_only and not args.track_b_only:
        if args.track_a.exists() and args.track_b.exists():
            track_a_results = load_jsonl(args.track_a)
            track_b_results = load_jsonl(args.track_b)
            track_a_metrics = calculate_track_a_metrics(track_a_results)
            track_b_metrics = calculate_track_b_metrics(track_b_results)
            combined_report = format_combined_report(track_a_metrics, track_b_metrics)
            reports.append(combined_report)
            print(f"\n{combined_report}")

    # Write summary to file
    if reports:
        with args.out.open("w", encoding="utf-8") as f:
            f.write("\n\n".join(reports))
        print(f"\n\nWrote summary to {args.out}")


if __name__ == "__main__":
    main()

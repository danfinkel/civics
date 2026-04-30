"""
w1_eval.py — Batch extraction eval for W1 warm-up experiments.

Runs the extraction prompt N times per input, scores each run against
ground truth, and produces a summary report with stability metrics.

Usage:
    pip install pillow pdf2image ollama

    # Run 10x against both clean and degraded:
    python w1_eval.py --runs 10 D03-clean.pdf D03-degraded.jpg

    # Also compare temperature settings:
    python w1_eval.py --runs 10 --temp 0 D03-clean.pdf D03-degraded.jpg

Output:
    - Prints a per-field summary table to stdout
    - Writes w1_eval_results.json with full raw results for later analysis
"""

import ollama
import base64
import json
import sys
import io
import argparse
import time
from pathlib import Path
from collections import defaultdict

# ── Ground truth ──────────────────────────────────────────────────────────────
# Update these if you change the document values.
GROUND_TRUTH = {
    "employer_name":    "Synthetic Corp LLC",
    "employee_name":    "Maria Gonzalez-Reyes",
    "pay_period_start": "March 15, 2026",
    "pay_period_end":   "March 28, 2026",
    "gross_income":     "$1,847.50",
    "net_income":       "$1,324.85",
    "pay_date":         "March 28, 2026",
}

FIELDS = list(GROUND_TRUTH.keys())

# ── Prompt ────────────────────────────────────────────────────────────────────
PROMPT = """Read this document and extract the following fields as JSON.

Rules:
- For gross_income, extract ONLY the current period gross pay, not the YTD total.
- For net_income, extract ONLY the "This Period" net pay from the Net Pay box, not YTD and not total deductions.
- If you cannot read a field clearly, set its value to "UNREADABLE". Never guess or infer.
- Return ONLY a valid JSON object. No explanation, no markdown fences.

{
  "employer_name": "",
  "employee_name": "",
  "pay_period_start": "",
  "pay_period_end": "",
  "gross_income": "",
  "net_income": "",
  "pay_date": ""
}"""

# ── Image loading ─────────────────────────────────────────────────────────────

def to_jpeg_b64(path: Path) -> str:
    """Convert any image or single-page PDF to a base64 JPEG string."""
    from PIL import Image
    if path.suffix.lower() == ".pdf":
        from pdf2image import convert_from_path
        pages = convert_from_path(str(path), dpi=150)
        img = pages[0].convert("RGB")
    else:
        img = Image.open(path).convert("RGB")
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=90)
    return base64.b64encode(buf.getvalue()).decode()

# ── Scoring ───────────────────────────────────────────────────────────────────

def normalize(val: str) -> str:
    """Lowercase, strip whitespace and currency symbols for loose comparison."""
    return val.lower().strip().replace(",", "").replace("$", "").replace(" ", "")

def score_field(field: str, extracted: str, expected: str) -> dict:
    """
    Returns a score dict:
      exact   — 2pts: extracted matches expected exactly (after normalization)
      partial — 1pt:  expected value is contained in extracted or vice versa
      unreadable — 0pts but NOT a hallucination; model correctly abstained
      wrong   — 0pts: wrong value returned
      hallucinated — -1pt: confident wrong value (not UNREADABLE)
    """
    if extracted is None:
        return {"score": 0, "label": "missing", "note": "field absent from JSON"}

    ext_n = normalize(extracted)
    exp_n = normalize(expected)

    if ext_n == "unreadable":
        return {"score": 0, "label": "unreadable", "note": "model abstained"}

    if ext_n == exp_n:
        return {"score": 2, "label": "exact", "note": ""}

    if exp_n in ext_n or ext_n in exp_n:
        return {"score": 1, "label": "partial", "note": f"got '{extracted}'"}

    # Wrong value — check if it's a plausible number from the document
    # (hallucination by misattribution) vs. completely fabricated
    return {"score": -1, "label": "hallucinated", "note": f"got '{extracted}', expected '{expected}'"}

def parse_response(raw: str) -> dict:
    """Best-effort JSON parse — strips markdown fences if present."""
    cleaned = raw.strip()
    if cleaned.startswith("```"):
        lines = cleaned.split("\n")
        cleaned = "\n".join(lines[1:-1] if lines[-1].strip() == "```" else lines[1:])
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        return None

# ── Single run ────────────────────────────────────────────────────────────────

def run_once(img_b64: str, temperature: float) -> dict:
    """Run one extraction and return parsed result + raw output."""
    start = time.time()
    r = ollama.chat(
        model="gemma4:e2b",
        messages=[{
            "role": "user",
            "content": PROMPT,
            "images": [img_b64],
        }],
        options={"temperature": temperature},
    )
    elapsed = time.time() - start
    raw = r["message"]["content"]
    parsed = parse_response(raw)
    return {"raw": raw, "parsed": parsed, "elapsed_s": round(elapsed, 2)}

# ── Batch eval for one input file ─────────────────────────────────────────────

def eval_file(path: Path, n_runs: int, temperature: float) -> dict:
    print(f"\n{'='*56}")
    print(f"  {path.name}  |  {n_runs} runs  |  temp={temperature}")
    print(f"{'='*56}")

    img_b64 = to_jpeg_b64(path)

    runs = []
    parse_failures = 0

    for i in range(n_runs):
        result = run_once(img_b64, temperature)
        status = "✓" if result["parsed"] else "✗"
        print(f"  Run {i+1:>2}/{n_runs}  {status}  ({result['elapsed_s']}s)", end="")

        if result["parsed"] is None:
            parse_failures += 1
            print("  ← JSON parse failed")
        else:
            # Quick inline summary of key fields
            p = result["parsed"]
            gross = p.get("gross_income", "?")
            net   = p.get("net_income", "?")
            print(f"  gross={gross}  net={net}")

        runs.append(result)

    # ── Score each run ────────────────────────────────────────────────────────
    field_scores = defaultdict(list)   # field → list of score dicts
    all_extracted = defaultdict(list)  # field → list of extracted values

    for run in runs:
        if run["parsed"] is None:
            continue
        for field in FIELDS:
            extracted = run["parsed"].get(field)
            expected  = GROUND_TRUTH[field]
            sc = score_field(field, extracted, expected)
            field_scores[field].append(sc)
            all_extracted[field].append(extracted or "MISSING")

    # ── Per-field summary ─────────────────────────────────────────────────────
    print(f"\n  Field-level summary ({n_runs - parse_failures} parseable runs):\n")
    print(f"  {'Field':<22} {'Avg':>5}  {'Exact':>5}  {'Partial':>7}  {'UNREAD':>6}  {'Halluc':>6}  {'Stability'}")
    print(f"  {'-'*22} {'-'*5}  {'-'*5}  {'-'*7}  {'-'*6}  {'-'*6}  {'-'*20}")

    summary = {}
    for field in FIELDS:
        scores = field_scores[field]
        if not scores:
            print(f"  {field:<22}  (no data)")
            continue

        labels     = [s["label"] for s in scores]
        pts        = [s["score"] for s in scores]
        avg        = sum(pts) / len(pts)
        n_exact    = labels.count("exact")
        n_partial  = labels.count("partial")
        n_unread   = labels.count("unreadable")
        n_halluc   = labels.count("hallucinated")

        # Stability: most common extracted value
        vals = all_extracted[field]
        most_common = max(set(vals), key=vals.count)
        stability_count = vals.count(most_common)
        stability = f"{most_common[:18]!r} ({stability_count}/{len(vals)})"

        print(f"  {field:<22} {avg:>5.1f}  {n_exact:>5}  {n_partial:>7}  {n_unread:>6}  {n_halluc:>6}  {stability}")

        summary[field] = {
            "avg_score": round(avg, 2),
            "exact": n_exact,
            "partial": n_partial,
            "unreadable": n_unread,
            "hallucinated": n_halluc,
            "most_common_value": most_common,
            "stability_fraction": round(stability_count / len(vals), 2),
        }

    # ── Top-level metrics ─────────────────────────────────────────────────────
    all_scores = [s["score"] for scores in field_scores.values() for s in scores]
    all_labels = [s["label"] for scores in field_scores.values() for s in scores]
    max_possible = len([s for s in all_scores if s >= 0]) * 2  # exclude -1 from denominator
    accuracy_pct = round(
        sum(s for s in all_scores if s > 0) / max(max_possible, 1) * 100, 1
    )
    halluc_rate = round(all_labels.count("hallucinated") / max(len(all_labels), 1) * 100, 1)
    parse_rate  = round((n_runs - parse_failures) / n_runs * 100, 1)

    print(f"\n  ── Top-level metrics ──────────────────────────────────")
    print(f"  Extraction accuracy (clean scoring):  {accuracy_pct}%  (target ≥80%)")
    print(f"  Hallucination rate:                   {halluc_rate}%  (target ≤5%)")
    print(f"  JSON parseable:                       {parse_rate}%  (target ≥95%)")
    print(f"  Parse failures:                       {parse_failures}/{n_runs}")

    return {
        "file": path.name,
        "n_runs": n_runs,
        "temperature": temperature,
        "parse_failures": parse_failures,
        "accuracy_pct": accuracy_pct,
        "hallucination_rate_pct": halluc_rate,
        "json_parseable_pct": parse_rate,
        "fields": summary,
        "raw_runs": runs,
    }

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="W1 batch extraction eval")
    parser.add_argument("files", nargs="+", help="Input files (PDF or image)")
    parser.add_argument("--runs", type=int, default=10, help="Number of runs per file (default: 10)")
    parser.add_argument("--temp", type=float, default=0.0, help="Model temperature (default: 0)")
    parser.add_argument("--out", type=str, default="w1_eval_results.json", help="Output JSON file")
    args = parser.parse_args()

    all_results = []
    for f in args.files:
        path = Path(f)
        if not path.exists():
            print(f"File not found: {f}")
            continue
        result = eval_file(path, args.runs, args.temp)
        all_results.append(result)

    # Save full results
    out_path = Path(args.out)
    # Strip raw_runs from saved JSON to keep it readable (keep if you want full logs)
    for r in all_results:
        del r["raw_runs"]
    out_path.write_text(json.dumps(all_results, indent=2))
    print(f"\n\nResults saved to {out_path}")

    # ── Cross-file comparison (if >1 file) ───────────────────────────────────
    if len(all_results) > 1:
        print(f"\n{'='*56}")
        print("  CROSS-FILE COMPARISON")
        print(f"{'='*56}")
        print(f"  {'File':<28} {'Accuracy':>9}  {'Halluc%':>8}  {'ParseOK%':>9}")
        print(f"  {'-'*28} {'-'*9}  {'-'*8}  {'-'*9}")
        for r in all_results:
            print(f"  {r['file']:<28} {r['accuracy_pct']:>8}%  {r['hallucination_rate_pct']:>7}%  {r['json_parseable_pct']:>8}%")
        print()


if __name__ == "__main__":
    main()
"""
w4_match.py — W4 proof-category matching (document vs requested proof type).

For each input file, runs the matching prompt N times with the same category
definition. Same image pipeline as w1/w2/w3.

Usage:
    uv run --group dev python w4_match.py path/to/doc.pdf

    python w4_match.py --category "EARNED INCOME" --runs 5 a.pdf b.jpg

Output: stdout per run + w4_match_results.json next to this script.
"""

from __future__ import annotations

import argparse
import base64
import io
import json
import sys
import time
from collections import Counter
from pathlib import Path

import ollama

DEFAULT_CATEGORY = "EARNED INCOME"

DEFAULT_DEFINITION = (
    "Acceptable earned income proof includes recent pay stubs from the last 30 days, "
    "employer letters on company letterhead, or recent self-employment records with "
    "income and expense documentation."
)


def build_prompt(category: str, definition: str) -> str:
    return f"""The document to evaluate is attached as an image.

Proof category requested: {category}

Category definition: {definition}

Does this document appear to satisfy this proof category?

Return JSON:
{{
  "assessment": "likely_satisfies | likely_does_not_satisfy | insufficient_information",
  "confidence": "high | medium | low",
  "evidence": "[quote the specific text from the document that supports your assessment]",
  "caveats": "[any concerns about date range, legibility, or policy edge cases]"
}}

Return ONLY valid JSON. No markdown, no explanation."""


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


def parse_response(raw: str) -> dict | None:
    cleaned = raw.strip()
    if cleaned.startswith("```"):
        lines = cleaned.split("\n")
        cleaned = "\n".join(lines[1:-1] if lines[-1].strip() == "```" else lines[1:])
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        return None


def run_once(img_b64: str, prompt: str, model: str, temperature: float) -> dict:
    start = time.time()
    r = ollama.chat(
        model=model,
        messages=[
            {
                "role": "user",
                "content": prompt,
                "images": [img_b64],
            }
        ],
        options={"temperature": temperature},
    )
    elapsed = time.time() - start
    raw = r["message"]["content"]
    return {"raw": raw, "parsed": parse_response(raw), "elapsed_s": round(elapsed, 2)}


def eval_file(
    path: Path,
    n_runs: int,
    model: str,
    temperature: float,
    category: str,
    definition: str,
) -> dict:
    prompt = build_prompt(category, definition)
    print(f"\n{'=' * 60}")
    print(f"  {path.name}  |  category={category!r}  |  {n_runs} runs  |  {model}  temp={temperature}")
    print(f"{'=' * 60}")

    img_b64 = to_jpeg_b64(path)
    runs: list[dict] = []
    parse_failures = 0

    for i in range(n_runs):
        result = run_once(img_b64, prompt, model, temperature)
        runs.append(result)
        ok = result["parsed"] is not None
        if not ok:
            parse_failures += 1
        status = "✓" if ok else "✗"
        print(f"\n--- run {i + 1}/{n_runs}  {status}  ({result['elapsed_s']}s) ---")
        print(result["raw"].rstrip())

    assessments: list[str] = []
    confidences: list[str] = []
    for r in runs:
        p = r["parsed"]
        if not p:
            continue
        a = p.get("assessment")
        c = p.get("confidence")
        if a is not None:
            assessments.append(str(a).strip().lower().replace(" ", "_"))
        if c is not None:
            confidences.append(str(c).strip().lower())

    # Normalize assessment labels for counting (model may return spaces)
    norm_map = {
        "likely_satisfies": "likely_satisfies",
        "likely_does_not_satisfy": "likely_does_not_satisfy",
        "insufficient_information": "insufficient_information",
    }
    assessments_norm = []
    for a in assessments:
        key = a.replace(" ", "_")
        assessments_norm.append(norm_map.get(key, key))

    print(f"\n  Summary: parseable {(n_runs - parse_failures)}/{n_runs}")
    if assessments_norm:
        print(f"  assessment: {dict(Counter(assessments_norm))}")
    if confidences:
        print(f"  confidence: {dict(Counter(confidences))}")

    return {
        "file": str(path),
        "file_name": path.name,
        "proof_category": category,
        "category_definition": definition,
        "n_runs": n_runs,
        "model": model,
        "temperature": temperature,
        "parse_failures": parse_failures,
        "runs": runs,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="W4 document vs proof category matching")
    parser.add_argument("files", nargs="+", help="Document images or PDFs")
    parser.add_argument("--runs", type=int, default=5, help="Runs per file (default: 5)")
    parser.add_argument("--temp", type=float, default=0.0, help="Model temperature (default: 0)")
    parser.add_argument(
        "--model",
        type=str,
        default="gemma4:e2b",
        help='Ollama model (default: "gemma4:e2b")',
    )
    parser.add_argument(
        "--category",
        type=str,
        default=DEFAULT_CATEGORY,
        help=f'Proof category label (default: "{DEFAULT_CATEGORY}")',
    )
    parser.add_argument(
        "--definition",
        type=str,
        default="",
        help="Category definition text (default: built-in EARNED INCOME definition)",
    )
    parser.add_argument(
        "--out",
        type=str,
        default="",
        help="Results JSON path (default: w4_match_results.json beside this script)",
    )
    args = parser.parse_args()

    definition = args.definition.strip() if args.definition.strip() else DEFAULT_DEFINITION
    out_path = (
        Path(args.out)
        if args.out
        else Path(__file__).resolve().parent / "w4_match_results.json"
    )

    all_results: list[dict] = []
    for f in args.files:
        path = Path(f)
        if not path.exists():
            print(f"File not found: {f}", file=sys.stderr)
            continue
        all_results.append(
            eval_file(path, args.runs, args.model, args.temp, args.category, definition)
        )

    serializable = []
    for block in all_results:
        slim_runs = [
            {"raw": r["raw"], "parsed": r["parsed"], "elapsed_s": r["elapsed_s"]}
            for r in block["runs"]
        ]
        serializable.append(
            {**{k: v for k, v in block.items() if k != "runs"}, "runs": slim_runs}
        )

    out_path.write_text(json.dumps(serializable, indent=2))
    print(f"\n\nFull run log saved to {out_path}")


if __name__ == "__main__":
    main()

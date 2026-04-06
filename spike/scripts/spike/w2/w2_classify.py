"""
w2_classify.py — Document type classification (blind label) for W2.

Runs the classification prompt N times per input and prints raw model output
plus a short stability summary. Uses the same image pipeline as w1_eval.py.

Usage:
    pip install pillow pdf2image ollama

    python w2_classify.py path/to/doc.pdf path/to/doc.jpg

    python w2_classify.py --runs 5 --temp 0 "$SPIKE/artifacts/clean/D01.pdf"
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

PROMPT = """Look at this document. What type of document is it?

Answer with exactly one of these labels:
pay_stub | bank_statement | lease_agreement | utility_bill |
phone_bill | government_notice | government_award_letter |
identity_document | birth_certificate | immunization_record |
handwritten_letter | affidavit | other

Return JSON:
{
  "classification": "",
  "confidence": "high | medium | low",
  "evidence": "one sentence quoting the specific text or visual element that led to your classification"
}

Return ONLY the JSON. No markdown, no explanation."""


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


def run_once(img_b64: str, model: str, temperature: float) -> dict:
    start = time.time()
    r = ollama.chat(
        model=model,
        messages=[
            {
                "role": "user",
                "content": PROMPT,
                "images": [img_b64],
            }
        ],
        options={"temperature": temperature},
    )
    elapsed = time.time() - start
    raw = r["message"]["content"]
    return {"raw": raw, "parsed": parse_response(raw), "elapsed_s": round(elapsed, 2)}


def classify_file(path: Path, n_runs: int, model: str, temperature: float) -> dict:
    print(f"\n{'=' * 60}")
    print(f"  {path.name}  |  {n_runs} runs  |  model={model}  temp={temperature}")
    print(f"{'=' * 60}")

    img_b64 = to_jpeg_b64(path)
    runs: list[dict] = []
    parse_failures = 0

    for i in range(n_runs):
        result = run_once(img_b64, model, temperature)
        runs.append(result)
        ok = result["parsed"] is not None
        if not ok:
            parse_failures += 1
        status = "✓" if ok else "✗"
        print(f"\n--- run {i + 1}/{n_runs}  {status}  ({result['elapsed_s']}s) ---")
        print(result["raw"].rstrip())

    labels = []
    confidences = []
    for r in runs:
        p = r["parsed"]
        if not p:
            continue
        c = p.get("classification")
        if c is not None:
            labels.append(str(c).strip())
        conf = p.get("confidence")
        if conf is not None:
            confidences.append(str(conf).strip().lower())

    print(f"\n  Summary: parseable {(n_runs - parse_failures)}/{n_runs}")
    if labels:
        ctr = Counter(labels)
        print(f"  Classifications: {dict(ctr)}")
    if confidences:
        print(f"  Confidence counts: {dict(Counter(confidences))}")

    return {
        "file": str(path),
        "file_name": path.name,
        "n_runs": n_runs,
        "model": model,
        "temperature": temperature,
        "parse_failures": parse_failures,
        "runs": runs,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="W2 blind document-type classification")
    parser.add_argument("files", nargs="+", help="Input files (PDF or image)")
    parser.add_argument("--runs", type=int, default=5, help="Runs per file (default: 5)")
    parser.add_argument("--temp", type=float, default=0.0, help="Model temperature (default: 0)")
    parser.add_argument(
        "--model",
        type=str,
        default="gemma4:e2b",
        help='Ollama model name (default: "gemma4:e2b" to match w1)',
    )
    parser.add_argument(
        "--out",
        type=str,
        default="",
        help="Write full results JSON (default: w2_classify_results.json next to this script)",
    )
    args = parser.parse_args()

    out_path = Path(args.out) if args.out else Path(__file__).resolve().parent / "w2_classify_results.json"

    all_results: list[dict] = []
    for f in args.files:
        path = Path(f)
        if not path.exists():
            print(f"File not found: {f}", file=sys.stderr)
            continue
        all_results.append(classify_file(path, args.runs, args.model, args.temp))

    # Strip huge base64 from saved copy (image is same per file)
    serializable = []
    for block in all_results:
        slim_runs = []
        for r in block["runs"]:
            slim_runs.append({"raw": r["raw"], "parsed": r["parsed"], "elapsed_s": r["elapsed_s"]})
        serializable.append({**{k: v for k, v in block.items() if k != "runs"}, "runs": slim_runs})

    out_path.write_text(json.dumps(serializable, indent=2))
    print(f"\n\nFull run log saved to {out_path}")


if __name__ == "__main__":
    main()

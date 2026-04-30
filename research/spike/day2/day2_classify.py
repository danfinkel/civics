"""
Day 2 Step 1 — Document Classification

Runs classification prompt against degraded artifacts (and D16 specifically for Spanish testing).
Scores against gold classification labels from ground_truth.csv.

Example:
  cd spike/scripts/day2
  python day2_classify.py --artifacts D01,D03 --runs 1
  python day2_classify.py  # all 16 artifacts
"""

from __future__ import annotations

import argparse
import base64
import csv
import io
import json
import sys
import time
from collections import defaultdict
from pathlib import Path

import httpx
import ollama

SCRIPT_DIR = Path(__file__).resolve().parent
SPIKE_DIR = SCRIPT_DIR.parent.parent
DEFAULT_GT = SPIKE_DIR / "artifacts" / "clean" / "html" / "ground_truth.csv"
CLEAN_DIR = SPIKE_DIR / "artifacts" / "clean"
DEGRADED_DIR = SPIKE_DIR / "artifacts" / "degraded"
BLURRY_DIR = SPIKE_DIR / "artifacts" / "blurry"

# Gold classification labels per artifact (from DAY2_PLAN.md)
GOLD_CLASSIFICATIONS = {
    "D01": "government_notice",
    "D02": "government_notice",
    "D03": "pay_stub",
    "D04": "pay_stub",
    "D05": "lease_agreement",
    "D06": "utility_bill",
    "D07": "phone_bill",
    "D08": "handwritten_letter",
    "D09": "identity_document",
    "D10": "government_award_letter",
    "D11": "other",
    "D12": "birth_certificate",
    "D13": "immunization_record",
    "D14": "lease_agreement",
    "D15": "affidavit",
    "D16": "utility_bill",
}

CLASSIFICATION_PROMPT = """Look at this document image. Classify it into exactly one category:

pay_stub | bank_statement | lease_agreement | utility_bill |
phone_bill | government_notice | government_award_letter |
identity_document | birth_certificate | immunization_record |
handwritten_letter | affidavit | other

Return JSON:
{
  "classification": "",
  "confidence": "high|medium|low",
  "evidence": "[one sentence quoting the specific text or layout element that led to your classification]"
}

Return ONLY valid JSON. No markdown, no explanation.
"""


def to_jpeg_b64(path: Path, *, pdf_dpi: int = 150, jpeg_quality: int = 90) -> str:
    from PIL import Image

    if path.suffix.lower() == ".pdf":
        from pdf2image import convert_from_path

        pages = convert_from_path(str(path), dpi=pdf_dpi)
        img = pages[0].convert("RGB")
    else:
        img = Image.open(path).convert("RGB")
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=jpeg_quality)
    return base64.b64encode(buf.getvalue()).decode()


def parse_response(raw: str) -> dict | None:
    """Parse model response, handling markdown fences and common JSON issues."""
    cleaned = raw.strip()
    if cleaned.startswith("```"):
        lines = cleaned.split("\n")
        cleaned = "\n".join(lines[1:-1] if lines[-1].strip() == "```" else lines[1:])
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        import re

        json_pattern = r"\{[\s\S]*\}"
        match = re.search(json_pattern, cleaned)
        if match:
            try:
                return json.loads(match.group(0))
            except json.JSONDecodeError:
                pass

        # E4B fix: Try wrapping bare key:value pairs in braces
        if cleaned and not cleaned.startswith("{") and not cleaned.startswith("["):
            if '"' in cleaned and ":" in cleaned:
                try:
                    wrapped = "{" + cleaned + "}"
                    return json.loads(wrapped)
                except json.JSONDecodeError:
                    pass

        return None


def score_classification(extracted: str | None, expected: str) -> dict:
    """Score classification result."""
    if extracted is None or not str(extracted).strip():
        return {"score": 0, "label": "missing", "note": "empty or null response"}

    ext = str(extracted).strip().lower()
    exp = expected.strip().lower()

    # D11 edge case: "other" is gold but reasonable alternatives are acceptable
    if exp == "other":
        if ext == "other":
            return {"score": 2, "label": "exact", "note": ""}
        # Soft pass for reasonable non-taxonomy labels
        return {"score": 1, "label": "soft_pass", "note": f"expected 'other', got '{extracted}' — manual review needed"}

    if ext == exp:
        return {"score": 2, "label": "exact", "note": ""}

    return {"score": 0, "label": "wrong", "note": f"expected '{expected}', got '{extracted}'"}


def resolve_input(aid: str, variant: str) -> Path | None:
    """Resolve artifact path, trying multiple naming conventions."""
    if variant == "clean":
        # Try -clean suffix first, then plain name
        for suffix in [f"{aid}-clean.pdf", f"{aid}.pdf"]:
            p = CLEAN_DIR / suffix
            if p.exists():
                return p
        return None
    if variant == "degraded":
        p = DEGRADED_DIR / f"{aid}-degraded.jpg"
        return p if p.exists() else None
    if variant == "blurry":
        p = BLURRY_DIR / f"{aid}-blurry.jpg"
        return p if p.exists() else None
    return None


def run_classification(
    client: ollama.Client,
    image_b64: str,
    model: str,
    temperature: float,
) -> tuple[dict | None, str, float]:
    t0 = time.time()
    r = client.chat(
        model=model,
        messages=[
            {"role": "user", "content": CLASSIFICATION_PROMPT, "images": [image_b64]}
        ],
        options={"temperature": temperature},
    )
    elapsed = time.time() - t0
    raw = r.get("message", {}).get("content") or ""
    parsed = parse_response(raw)
    return parsed, raw, elapsed


def main() -> None:
    ap = argparse.ArgumentParser(description="Day 2 Step 1 — Document Classification")
    ap.add_argument("--ground-truth", type=Path, default=DEFAULT_GT)
    ap.add_argument(
        "--artifacts",
        type=str,
        default="",
        help="Comma-separated artifact IDs (e.g. D01,D03). Default: all 16 artifacts.",
    )
    ap.add_argument(
        "--variants",
        type=str,
        default="degraded",
        help="Variants to test: clean, degraded, blurry (default: degraded)",
    )
    ap.add_argument("--runs", type=int, default=1, help="Runs per input")
    ap.add_argument("--model", type=str, default="gemma4:e4b")
    ap.add_argument("--temp", type=float, default=0.0)
    ap.add_argument(
        "--out", type=Path, default=SCRIPT_DIR / "day2_classification_results.jsonl"
    )
    ap.add_argument(
        "--append",
        action="store_true",
        help="Append to output JSONL instead of truncating",
    )
    ap.add_argument(
        "--http-timeout", type=float, default=900.0, help="Ollama HTTP timeout"
    )
    ap.add_argument("--pdf-dpi", type=int, default=150)
    ap.add_argument("--jpeg-quality", type=int, default=90)
    args = ap.parse_args()

    artifact_ids = (
        [x.strip() for x in args.artifacts.split(",") if x.strip()]
        if args.artifacts
        else sorted(GOLD_CLASSIFICATIONS.keys(), key=lambda s: (len(s), s))
    )
    variants = [v.strip() for v in args.variants.split(",") if v.strip()]

    timeout = httpx.Timeout(args.http_timeout)
    client = ollama.Client(timeout=timeout)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    out_mode = "a" if args.append else "w"
    n_written = 0
    out_f = args.out.open(out_mode, encoding="utf-8")

    for aid in artifact_ids:
        gold_class = GOLD_CLASSIFICATIONS.get(aid)
        if not gold_class:
            print(f"Skipping {aid}: no gold classification", file=sys.stderr)
            continue

        for variant in variants:
            path = resolve_input(aid, variant)
            if path is None:
                print(f"Skip {aid} {variant}: file missing", file=sys.stderr)
                continue

            b64 = to_jpeg_b64(
                path, pdf_dpi=args.pdf_dpi, jpeg_quality=args.jpeg_quality
            )

            for run_idx in range(args.runs):
                parsed, raw, elapsed = run_classification(
                    client, b64, args.model, args.temp
                )

                classification = parsed.get("classification") if parsed else None
                confidence = parsed.get("confidence") if parsed else None
                evidence = parsed.get("evidence") if parsed else None

                score_result = score_classification(classification, gold_class)

                record = {
                    "artifact_id": aid,
                    "variant": variant,
                    "input_path": str(path),
                    "run": run_idx,
                    "model": args.model,
                    "temperature": args.temp,
                    "elapsed_s": round(elapsed, 2),
                    "parse_ok": parsed is not None,
                    "classification": classification,
                    "confidence": confidence,
                    "evidence": evidence,
                    "gold_classification": gold_class,
                    "score": score_result["score"],
                    "score_label": score_result["label"],
                    "score_note": score_result["note"],
                    "raw_response": raw,
                }

                out_f.write(json.dumps(record, ensure_ascii=False) + "\n")
                out_f.flush()
                n_written += 1

                label = "ok" if parsed else "parse_fail"
                correct = "✓" if score_result["score"] >= 1 else "✗"
                print(
                    f"{aid} {variant} run{run_idx} {label} {correct} ({elapsed:.1f}s)",
                    flush=True,
                )

    out_f.close()
    print(f"Wrote {n_written} records to {args.out}")


if __name__ == "__main__":
    main()

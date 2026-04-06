#!/usr/bin/env python3
"""
Compare vision vs OCR-text extraction for degraded document images (Ollama gemma4:e2b).

Pass A: image + prompt (same family as Day 1).
Pass B: pytesseract OCR → text-only prompt (no image).

Requires:
  - ollama, pillow, pytesseract (dev group: uv sync --group dev)
  - Tesseract binary: brew install tesseract   (macOS)

Example:
  cd /path/to/civics
  uv run --group dev python spike/scripts/ocr_test.py \\
    spike/artifacts/degraded/D02-degraded.jpg \\
    spike/artifacts/degraded/D08-degraded.jpg \\
    spike/artifacts/degraded/D12-degraded.jpg
"""

from __future__ import annotations

import argparse
import base64
import io
import json
import sys
from pathlib import Path

import httpx
import ollama
import pytesseract
from PIL import Image

PROMPT_IMAGE = """Read this document and extract all fields you can identify as JSON.
Include: document_type, holder_or_account_name, primary_date,
secondary_date, key_amount_or_address, any_id_or_case_number.
For any field you cannot read, use "UNREADABLE".
Return ONLY valid JSON, no markdown."""

PROMPT_OCR_TEMPLATE = """The text below was extracted from the same document using OCR (optical character recognition).
It may contain misread characters, wrong line order, or noise. Infer the document fields from this text only.

--- OCR text ---
{ocr_text}
---

Extract all fields you can identify as JSON.
Include: document_type, holder_or_account_name, primary_date,
secondary_date, key_amount_or_address, any_id_or_case_number.
For any field you cannot read, use "UNREADABLE".
Return ONLY valid JSON, no markdown."""


def parse_json_response(raw: str) -> dict | None:
    cleaned = (raw or "").strip()
    if not cleaned:
        return None
    if cleaned.startswith("```"):
        lines = cleaned.split("\n")
        cleaned = "\n".join(lines[1:-1] if lines[-1].strip() == "```" else lines[1:])
    try:
        out = json.loads(cleaned)
        return out if isinstance(out, dict) else None
    except json.JSONDecodeError:
        return None


def image_to_jpeg_b64(path: Path, *, jpeg_quality: int = 90) -> str:
    img = Image.open(path).convert("RGB")
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=jpeg_quality)
    return base64.b64encode(buf.getvalue()).decode()


def run_image_pass(
    client: ollama.Client, model: str, image_b64: str, temperature: float
) -> tuple[str, dict | None]:
    r = client.chat(
        model=model,
        messages=[
            {"role": "user", "content": PROMPT_IMAGE, "images": [image_b64]},
        ],
        options={"temperature": temperature},
    )
    raw = r.get("message", {}).get("content") or ""
    return raw, parse_json_response(raw)


def run_text_pass(
    client: ollama.Client, model: str, text: str, temperature: float
) -> tuple[str, dict | None]:
    prompt = PROMPT_OCR_TEMPLATE.format(ocr_text=text.strip() or "(empty OCR)")
    r = client.chat(
        model=model,
        messages=[{"role": "user", "content": prompt}],
        options={"temperature": temperature},
    )
    raw = r.get("message", {}).get("content") or ""
    return raw, parse_json_response(raw)


def is_empty_string_value(v) -> bool:
    """True if missing, None, or whitespace-only (treat as 'empty string' for comparison)."""
    if v is None:
        return True
    if isinstance(v, str):
        return len(v.strip()) == 0
    return False


def ocr_improvement_keys(parsed_a: dict | None, parsed_b: dict | None) -> list[str]:
    """Keys where A is empty-string-like and B has a non-whitespace value."""
    if not parsed_b:
        return []
    keys = set()
    if parsed_a:
        keys |= set(parsed_a.keys())
    keys |= set(parsed_b.keys())
    keys |= {
        "document_type",
        "holder_or_account_name",
        "primary_date",
        "secondary_date",
        "key_amount_or_address",
        "any_id_or_case_number",
    }
    improved = []
    for k in sorted(keys):
        va = parsed_a.get(k) if parsed_a else None
        vb = parsed_b.get(k) if parsed_b else None
        if is_empty_string_value(va) and not is_empty_string_value(vb):
            improved.append(k)
    return improved


def main() -> None:
    ap = argparse.ArgumentParser(description="OCR vs image extraction comparison (Ollama)")
    ap.add_argument(
        "images",
        nargs="+",
        type=Path,
        help="Paths to degraded (or any) document images",
    )
    ap.add_argument("--model", default="gemma4:e2b", help="Ollama model name")
    ap.add_argument("--temp", type=float, default=0.0)
    ap.add_argument("--http-timeout", type=float, default=600.0)
    ap.add_argument("--jpeg-quality", type=int, default=90)
    args = ap.parse_args()

    client = ollama.Client(timeout=httpx.Timeout(args.http_timeout))

    for path in args.images:
        path = path.expanduser().resolve()
        if not path.is_file():
            print(f"\n{'='*72}\nSKIP (not a file): {path}\n", file=sys.stderr)
            continue

        print(f"\n{'='*72}")
        print(f"FILE: {path}")
        print("=" * 72)

        try:
            ocr_text = pytesseract.image_to_string(Image.open(path))
        except pytesseract.TesseractNotFoundError:
            print(
                "ERROR: Tesseract executable not found. Install with: brew install tesseract",
                file=sys.stderr,
            )
            sys.exit(1)

        print(f"\n--- OCR preview (first 800 chars) ---\n{ocr_text[:800]!r}\n")

        img_b64 = image_to_jpeg_b64(path, jpeg_quality=args.jpeg_quality)

        print("Running Pass A (image)…", flush=True)
        raw_a, parsed_a = run_image_pass(
            client, args.model, img_b64, args.temp
        )
        print("Running Pass B (OCR text only)…", flush=True)
        raw_b, parsed_b = run_text_pass(client, args.model, ocr_text, args.temp)

        print("\n--- Pass A (image) raw ---")
        print(raw_a if raw_a.strip() else "(empty response)")
        print("\n--- Pass B (OCR text) raw ---")
        print(raw_b if raw_b.strip() else "(empty response)")

        print("\n--- Pass A (image) parsed JSON ---")
        print(json.dumps(parsed_a, indent=2) if parsed_a else "(parse failed or empty)")
        print("\n--- Pass B (OCR) parsed JSON ---")
        print(json.dumps(parsed_b, indent=2) if parsed_b else "(parse failed or empty)")

        improved = ocr_improvement_keys(parsed_a, parsed_b)
        print("\n--- Comparison ---")
        if improved:
            print(
                "Pass B produced non-empty values where Pass A was empty/missing for keys:",
                ", ".join(improved),
            )
            for k in improved:
                va = parsed_a.get(k) if parsed_a else None
                vb = parsed_b.get(k)
                print(f"  {k}: A={va!r}  →  B={vb!r}")
        else:
            print(
                "No keys where Pass A was empty/missing and Pass B had a non-whitespace value."
            )


if __name__ == "__main__":
    main()

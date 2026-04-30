"""
Day 1 — Structured extraction at scale (feasibility spike).

Loads per-artifact fields from spike/artifacts/clean/html/ground_truth.csv,
runs the plan's extraction prompt against each artifact (clean PDF + degraded JPG
by default), writes JSONL results for scoring.

Dependencies: ollama, pillow, pdf2image (same as w1_eval).

Example:
  cd spike/scripts/day1
  python day1_extract.py --artifacts D01,D03 --runs 1
  python day1_extract.py  # all artifacts found in ground_truth.csv
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

PROMPT_PREFIX = """You are a document analysis assistant helping a resident prepare documents for a government process. Read the document carefully.

Rules (follow exactly):
- Extract only values clearly present in the document. Do not guess.
- Read each field value directly from its labeled location. Do not calculate or infer any value by arithmetic.
- For pay-stub income fields: use the current-period / this-period column only, not YTD, unless the field name explicitly says ytd.
- For name fields: copy text character-by-character as printed. If unclear, use UNREADABLE for that field.
- For date fields: use semantic labels as requested in the JSON keys (e.g. notice_date vs response_deadline).
- For form templates with labeled fields: read the FILLED IN values, not the template labels (e.g., if you see "CHILD'S NAME: Sofia", return "Sofia" not "CHILD'S NAME").
- If you cannot read a field with confidence, set its value to the string UNREADABLE (not a JSON object).
- If a field is not present in the document, return an empty string "" for that field.

Return ONLY valid JSON with exactly the keys listed below. No markdown fences, no commentary.
If your first attempt produces invalid JSON, retry and return only valid JSON.

Fields to extract (all string values):
"""


def load_ground_truth(path: Path) -> dict[str, dict[str, str]]:
    """artifact_id -> field_name -> expected_value"""
    by_artifact: dict[str, dict[str, str]] = defaultdict(dict)
    with path.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            aid = row["artifact_id"].strip()
            by_artifact[aid][row["field_name"].strip()] = row["expected_value"].strip()
    return dict(by_artifact)


def to_jpeg_b64(path: Path, *, pdf_dpi: int, jpeg_quality: int) -> str:
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


def build_prompt(fields: dict[str, str]) -> str:
    keys = list(fields.keys())
    lines = [PROMPT_PREFIX, "{"]
    for k in keys:
        lines.append(f'  "{k}": "",')
    lines.append("}")
    return "\n".join(lines)


def parse_response(raw: str) -> dict | None:
    """Parse model response, handling markdown fences and common JSON issues."""
    cleaned = raw.strip()
    if cleaned.startswith("```"):
        lines = cleaned.split("\n")
        cleaned = "\n".join(lines[1:-1] if lines[-1].strip() == "```" else lines[1:])
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        # Try to extract JSON from surrounding text
        import re
        json_pattern = r'\{[\s\S]*\}'
        match = re.search(json_pattern, cleaned)
        if match:
            try:
                return json.loads(match.group(0))
            except json.JSONDecodeError:
                pass

        # E4B fix: Try wrapping bare key:value pairs in braces
        # Detects patterns like "key": "value", "key2": "value2" without wrapping {}
        if cleaned and not cleaned.startswith("{") and not cleaned.startswith("["):
            # Check if it looks like JSON key-value pairs
            if '"' in cleaned and ":" in cleaned:
                try:
                    wrapped = "{" + cleaned + "}"
                    return json.loads(wrapped)
                except json.JSONDecodeError:
                    pass

        return None


def normalize(val: str) -> str:
    return val.lower().strip().replace(",", "").replace("$", "").replace(" ", "")


def score_field(extracted, expected: str) -> dict:
    """Score one field. Empty / null / whitespace-only responses are missing (0), never partial."""
    if isinstance(extracted, dict) and "value" in extracted:
        inner = extracted.get("value")
    elif isinstance(extracted, dict):
        inner = None
    else:
        inner = extracted

    if inner is None:
        return {"score": 0, "label": "missing", "note": "empty or null response"}
    if isinstance(inner, str):
        if not inner.strip():
            return {"score": 0, "label": "missing", "note": "empty or null response"}
        ext = inner
    else:
        ext = str(inner)
        if not ext.strip():
            return {"score": 0, "label": "missing", "note": "empty or null response"}

    ext_n = normalize(ext)
    exp_n = normalize(expected)
    if ext_n == "unreadable":
        return {"score": 0, "label": "unreadable", "note": ""}
    if ext_n == exp_n:
        return {"score": 2, "label": "exact", "note": ""}
    if exp_n in ext_n or ext_n in exp_n:
        return {"score": 1, "label": "partial", "note": ""}
    return {"score": -1, "label": "hallucinated", "note": ""}


def resolve_input(aid: str, variant: str) -> Path | None:
    if variant == "clean":
        p = CLEAN_DIR / f"{aid}-clean.pdf"
        return p if p.exists() else None
    if variant == "degraded":
        p = DEGRADED_DIR / f"{aid}-degraded.jpg"
        return p if p.exists() else None
    if variant == "blurry":
        p = BLURRY_DIR / f"{aid}-blurry.jpg"
        return p if p.exists() else None
    return None


def build_retry_prompt(fields: dict[str, str]) -> str:
    """Build a more explicit prompt for retry when first attempt returns empty values."""
    keys = list(fields.keys())
    lines = [
        PROMPT_PREFIX,
        "",
        "IMPORTANT: The previous attempt returned empty values. Please look carefully at the document",
        "and extract the actual data values shown. For form fields, return the FILLED values, not the labels.",
        "",
        "Fields to extract (all string values):",
        "{"
    ]
    for k in keys:
        lines.append(f'  "{k}": "",')
    lines.append("}")
    return "\n".join(lines)


def run_extraction(
    client: ollama.Client,
    image_b64: str,
    prompt: str,
    model: str,
    temperature: float,
    fields: dict[str, str] | None = None,
) -> tuple[dict | None, str, float]:
    t0 = time.time()
    r = client.chat(
        model=model,
        messages=[{"role": "user", "content": prompt, "images": [image_b64]}],
        options={"temperature": temperature},
    )
    elapsed = time.time() - t0
    raw = r.get("message", {}).get("content") or ""
    if not raw.strip():
        print(
            f"  warning: empty model content (done_reason={r.get('done_reason', '')!r})",
            file=sys.stderr,
            flush=True,
        )

    parsed = parse_response(raw)

    # Retry if all values are empty strings but we have fields to extract
    if parsed and fields:
        non_empty = [v for v in parsed.values() if v and str(v).strip() and str(v).strip() != "UNREADABLE"]
        if not non_empty and elapsed < 60:  # Only retry if we got a quick empty response
            print("  retrying with explicit prompt...", file=sys.stderr, flush=True)
            retry_prompt = build_retry_prompt(fields)
            r2 = client.chat(
                model=model,
                messages=[{"role": "user", "content": retry_prompt, "images": [image_b64]}],
                options={"temperature": temperature},
            )
            raw2 = r2.get("message", {}).get("content") or ""
            parsed2 = parse_response(raw2)
            if parsed2:
                # Use retry result if it has content
                non_empty2 = [v for v in parsed2.values() if v and str(v).strip() and str(v).strip() != "UNREADABLE"]
                if non_empty2:
                    return parsed2, raw2, elapsed + (time.time() - t0)

    return parsed, raw, elapsed


def main() -> None:
    ap = argparse.ArgumentParser(description="Day 1 batch extraction")
    ap.add_argument("--ground-truth", type=Path, default=DEFAULT_GT)
    ap.add_argument(
        "--artifacts",
        type=str,
        default="",
        help="Comma-separated artifact IDs (e.g. D01,D03). Default: all in ground truth.",
    )
    ap.add_argument("--variants", type=str, default="clean,degraded", help="clean,degraded,blurry")
    ap.add_argument("--runs", type=int, default=1, help="Runs per input (stability testing)")
    ap.add_argument("--model", type=str, default="gemma4:e2b")
    ap.add_argument("--temp", type=float, default=0.0)
    ap.add_argument("--out", type=Path, default=SCRIPT_DIR / "day1_extraction_results.jsonl")
    ap.add_argument("--skip-score", action="store_true", help="Do not compute per-field scores")
    ap.add_argument(
        "--append",
        action="store_true",
        help="Append to output JSONL instead of truncating (resume-friendly)",
    )
    ap.add_argument(
        "--jobs",
        type=str,
        default="",
        help="Targeted runs only, format: D01:degraded,D05:clean,D16:clean (overrides --variants cross-product)",
    )
    ap.add_argument(
        "--http-timeout",
        type=float,
        default=900.0,
        help="Ollama HTTP client read timeout in seconds (default 900)",
    )
    ap.add_argument("--pdf-dpi", type=int, default=150, help="Rasterize PDF at this DPI (default 150)")
    ap.add_argument("--jpeg-quality", type=int, default=90, help="JPEG quality 1-95 (default 90)")
    args = ap.parse_args()

    gt_path = args.ground_truth
    if not gt_path.exists():
        print(f"Ground truth not found: {gt_path}", file=sys.stderr)
        sys.exit(1)

    by_artifact = load_ground_truth(gt_path)
    wanted = [x.strip() for x in args.artifacts.split(",") if x.strip()]
    artifact_ids = wanted or sorted(by_artifact.keys(), key=lambda s: (len(s), s))
    variants = [v.strip() for v in args.variants.split(",") if v.strip()]

    if args.jobs.strip():
        job_pairs: list[tuple[str, str]] = []
        for part in args.jobs.split(","):
            part = part.strip()
            if not part:
                continue
            if ":" not in part:
                print(f"Invalid --jobs segment (need artifact:variant): {part}", file=sys.stderr)
                sys.exit(1)
            aid, var = part.split(":", 1)
            job_pairs.append((aid.strip(), var.strip()))
    else:
        job_pairs = [(a, v) for a in artifact_ids for v in variants]

    timeout = httpx.Timeout(args.http_timeout)
    client = ollama.Client(timeout=timeout)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    out_mode = "a" if args.append else "w"
    n_written = 0
    out_f = args.out.open(out_mode, encoding="utf-8")

    for aid, variant in job_pairs:
        fields = by_artifact.get(aid)
        if not fields:
            print(f"Skipping {aid}: no ground truth rows", file=sys.stderr)
            continue
        prompt = build_prompt(fields)
        path = resolve_input(aid, variant)
        if path is None:
            print(f"Skip {aid} {variant}: file missing", file=sys.stderr)
            continue
        b64 = to_jpeg_b64(
            path, pdf_dpi=args.pdf_dpi, jpeg_quality=args.jpeg_quality
        )
        for run_idx in range(args.runs):
            parsed, raw, elapsed = run_extraction(
                client, b64, prompt, args.model, args.temp, fields=fields
            )
            record = {
                "artifact_id": aid,
                "variant": variant,
                "input_path": str(path),
                "run": run_idx,
                "model": args.model,
                "temperature": args.temp,
                "pdf_dpi": args.pdf_dpi,
                "jpeg_quality": args.jpeg_quality,
                "http_timeout_s": args.http_timeout,
                "elapsed_s": round(elapsed, 2),
                "parse_ok": parsed is not None,
                "raw_response": raw,
                "parsed": parsed,
            }
            if parsed and not args.skip_score:
                scores = {}
                for fname, expected in fields.items():
                    scores[fname] = score_field(parsed.get(fname), expected)
                record["field_scores"] = scores
                pts = [s["score"] for s in scores.values()]
                record["avg_score"] = round(sum(pts) / len(pts), 3) if pts else None
                record["hallucination_count"] = sum(
                    1 for s in scores.values() if s["label"] == "hallucinated"
                )
            out_f.write(json.dumps(record, ensure_ascii=False) + "\n")
            out_f.flush()
            n_written += 1
            label = "ok" if parsed else "parse_fail"
            print(f"{aid} {variant} run{run_idx} {label} ({elapsed:.1f}s)", flush=True)

    out_f.close()
    print(f"Wrote {n_written} records to {args.out}")


if __name__ == "__main__":
    main()

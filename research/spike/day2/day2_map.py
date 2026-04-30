"""
Day 2 Step 2 — Category Mapping

Runs category mapping prompt against Track A and Track B relevant artifacts.
Scores against category_assessment fields in ground_truth.csv.

Prerequisites: Step 1 classification results (used as context in prompts).

Example:
  cd spike/scripts/day2
  python day2_map.py --artifacts D04,D05 --runs 1
  python day2_map.py  # all 8 mapping artifacts
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

# Mapping artifacts and their gold assessments (from DAY2_PLAN.md)
# Format: artifact_id -> (field_name, gold_answer, proof_category, definition_key)
MAPPING_ARTIFACTS = {
    "D04": (
        "category_assessment",
        "likely_does_not_satisfy",
        "EARNED INCOME",
        "earned_income",
    ),
    "D05": ("category_assessment", "likely_satisfies", "RESIDENCY (DTA / SNAP)", "residency"),
    "D06": ("category_assessment", "likely_satisfies", "RESIDENCY (DTA / SNAP)", "residency"),
    "D07": (
        "category_assessment",
        "residency_ambiguous",
        "RESIDENCY (DTA / SNAP)",
        "residency",
    ),
    "D08": ("category_assessment", "invalid_proof", "RESIDENCY (DTA / SNAP)", "residency"),
    "D10": (
        "category_assessment_vs_earned_income",
        "likely_does_not_satisfy",
        "EARNED INCOME",
        "earned_income",
    ),
    "D14": (
        "category_assessment_bps_two_leases",
        "same_residency_category_duplicate",
        "RESIDENCY (BPS two-category rule)",
        "residency_bps",
    ),
    "D16": ("category_assessment", "likely_satisfies", "RESIDENCY (DTA / SNAP)", "residency"),
}

# Category definitions (from DAY2_PLAN.md)
# NOTE: These definitions are artifact-specific to guide the model's assessment
CATEGORY_DEFINITIONS = {
    "earned_income": """Acceptable earned income proof includes recent pay stubs from the last 30 days, employer letters on company letterhead, or recent self-employment records with income and expense documentation. Documents must reflect income received within the past 30 days from the date of the verification notice.""",
    "residency": """Acceptable residency proof includes a current lease or rental agreement, utility bills (electric, gas, water) from the last 90 days showing the service address, bank statements showing the mailing address, or government mail addressed to the household. Cell phone bills are accepted by some DTA offices but policy varies by location. IMPORTANT: If the document is a phone bill or cell phone statement, return insufficient_information — acceptance is policy-dependent and varies by DTA office.""",
    "residency_bps": """Boston Public Schools requires TWO proofs of Boston residency from DIFFERENT categories. Valid categories are: lease or deed, utility bill, bank statement, government mail, employer letter, notarized affidavit. Two documents from the same category count as only ONE proof. Important: a lease and a second lease from the same address are the same category. IMPORTANT: If both documents are leases or both are from the same category, return same_residency_category_duplicate and name the specific rule violation in caveats.""",
}

# Document type hints for context (from gold classifications)
DOC_TYPE_HINTS = {
    "D04": "pay_stub",
    "D05": "lease_agreement",
    "D06": "utility_bill",
    "D07": "phone_bill",
    "D08": "handwritten_letter",
    "D10": "government_award_letter",
    "D14": "lease_agreement",
    "D16": "utility_bill",
}


def build_mapping_prompt(document_type: str, proof_category: str, definition: str) -> str:
    return f"""Document type: {document_type}

Requested proof category: {proof_category}

Category definition: {definition}

Does this document appear to satisfy this proof category?

Return JSON:
{{
  "assessment": "likely_satisfies|likely_does_not_satisfy|insufficient_information",
  "confidence": "high|medium|low",
  "evidence": "[exact quote from document supporting your answer]",
  "caveats": "[any concerns about date, legibility, policy edge cases]"
}}

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


def score_mapping(extracted: str | None, expected: str) -> dict:
    """
    Score mapping assessment result.

    Scale:
    - +2 (exact): model returns exact gold label
    - +1 (partial): right valence but wrong label
    - 0 (insufficient_information): model abstains
    - -1 (hallucinated): wrong valence
    """
    if extracted is None or not str(extracted).strip():
        return {"score": 0, "label": "missing", "note": "empty or null response"}

    ext = str(extracted).strip().lower()
    exp = expected.strip().lower()

    # Exact match
    if ext == exp:
        return {"score": 2, "label": "exact", "note": ""}

    # Model abstains
    if ext == "insufficient_information":
        return {"score": 0, "label": "abstain", "note": "model abstained"}

    # Right valence but wrong label (rejection cases)
    rejection_labels = {"likely_does_not_satisfy", "invalid_proof", "same_residency_category_duplicate"}
    acceptance_labels = {"likely_satisfies"}
    ambiguous_labels = {"residency_ambiguous"}

    exp_reject = exp in rejection_labels
    ext_reject = ext in rejection_labels
    exp_accept = exp in acceptance_labels
    ext_accept = ext in acceptance_labels
    exp_ambig = exp in ambiguous_labels
    ext_ambig = ext in ambiguous_labels

    # Both rejections = partial credit
    if exp_reject and ext_reject:
        return {"score": 1, "label": "partial", "note": f"expected '{expected}', got '{extracted}' — both rejections"}

    # Both ambiguous/uncertain = partial credit
    if (exp_ambig or exp_reject) and (ext_ambig or ext_reject):
        return {"score": 1, "label": "partial", "note": f"expected '{expected}', got '{extracted}' — correct uncertainty"}

    # Wrong valence = hallucination
    if (exp_accept and ext_reject) or (exp_reject and ext_accept):
        return {"score": -1, "label": "hallucinated", "note": f"expected '{expected}', got '{extracted}' — wrong valence"}

    # Default: partial for close but not exact
    return {"score": 1, "label": "partial", "note": f"expected '{expected}', got '{extracted}'"}


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
    return None


def run_mapping(
    client: ollama.Client,
    image_b64: str,
    prompt: str,
    model: str,
    temperature: float,
) -> tuple[dict | None, str, float]:
    t0 = time.time()
    r = client.chat(
        model=model,
        messages=[{"role": "user", "content": prompt, "images": [image_b64]}],
        options={"temperature": temperature},
    )
    elapsed = time.time() - t0
    raw = r.get("message", {}).get("content") or ""
    parsed = parse_response(raw)
    return parsed, raw, elapsed


def main() -> None:
    ap = argparse.ArgumentParser(description="Day 2 Step 2 — Category Mapping")
    ap.add_argument("--ground-truth", type=Path, default=DEFAULT_GT)
    ap.add_argument(
        "--artifacts",
        type=str,
        default="",
        help="Comma-separated artifact IDs. Default: all 8 mapping artifacts.",
    )
    ap.add_argument(
        "--variants",
        type=str,
        default="clean,degraded",
        help="Variants to test (default: clean,degraded)",
    )
    ap.add_argument("--runs", type=int, default=1, help="Runs per input")
    ap.add_argument("--model", type=str, default="gemma4:e4b")
    ap.add_argument("--temp", type=float, default=0.0)
    ap.add_argument(
        "--out", type=Path, default=SCRIPT_DIR / "day2_mapping_results.jsonl"
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
        else sorted(MAPPING_ARTIFACTS.keys(), key=lambda s: (len(s), s))
    )
    variants = [v.strip() for v in args.variants.split(",") if v.strip()]

    timeout = httpx.Timeout(args.http_timeout)
    client = ollama.Client(timeout=timeout)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    out_mode = "a" if args.append else "w"
    n_written = 0
    out_f = args.out.open(out_mode, encoding="utf-8")

    for aid in artifact_ids:
        mapping_info = MAPPING_ARTIFACTS.get(aid)
        if not mapping_info:
            print(f"Skipping {aid}: not a mapping artifact", file=sys.stderr)
            continue

        field_name, gold_answer, proof_category, def_key = mapping_info
        definition = CATEGORY_DEFINITIONS[def_key]
        doc_type = DOC_TYPE_HINTS.get(aid, "unknown")

        for variant in variants:
            path = resolve_input(aid, variant)
            if path is None:
                print(f"Skip {aid} {variant}: file missing", file=sys.stderr)
                continue

            b64 = to_jpeg_b64(
                path, pdf_dpi=args.pdf_dpi, jpeg_quality=args.jpeg_quality
            )

            prompt = build_mapping_prompt(doc_type, proof_category, definition)

            for run_idx in range(args.runs):
                parsed, raw, elapsed = run_mapping(
                    client, b64, prompt, args.model, args.temp
                )

                assessment = parsed.get("assessment") if parsed else None
                confidence = parsed.get("confidence") if parsed else None
                evidence = parsed.get("evidence") if parsed else None
                caveats = parsed.get("caveats") if parsed else None

                score_result = score_mapping(assessment, gold_answer)

                # Flag critical cases
                critical_flags = []
                if aid == "D10" and assessment == "likely_satisfies":
                    critical_flags.append("DANGER: award letter accepted as earned income")
                if aid == "D07" and assessment == "likely_satisfies" and confidence == "high":
                    critical_flags.append("WARNING: overconfident acceptance of policy-ambiguous document")
                if aid == "D08" and assessment not in {"invalid_proof", "likely_does_not_satisfy"}:
                    critical_flags.append("DANGER: handwritten note not rejected")
                if aid == "D14" and assessment != "same_residency_category_duplicate":
                    critical_flags.append("WARNING: duplicate category violation not detected")

                record = {
                    "artifact_id": aid,
                    "variant": variant,
                    "input_path": str(path),
                    "run": run_idx,
                    "model": args.model,
                    "temperature": args.temp,
                    "elapsed_s": round(elapsed, 2),
                    "parse_ok": parsed is not None,
                    "document_type": doc_type,
                    "proof_category": proof_category,
                    "assessment": assessment,
                    "confidence": confidence,
                    "evidence": evidence,
                    "caveats": caveats,
                    "gold_assessment": gold_answer,
                    "gold_field": field_name,
                    "score": score_result["score"],
                    "score_label": score_result["label"],
                    "score_note": score_result["note"],
                    "critical_flags": critical_flags,
                    "raw_response": raw,
                }

                out_f.write(json.dumps(record, ensure_ascii=False) + "\n")
                out_f.flush()
                n_written += 1

                label = "ok" if parsed else "parse_fail"
                correct = "✓" if score_result["score"] >= 1 else "✗"
                if score_result["score"] == -1:
                    correct = "!!"
                crit = " [CRITICAL]" if critical_flags else ""
                print(
                    f"{aid} {variant} run{run_idx} {label} {correct}{crit} ({elapsed:.1f}s)",
                    flush=True,
                )

    out_f.close()
    print(f"Wrote {n_written} records to {args.out}")


if __name__ == "__main__":
    main()

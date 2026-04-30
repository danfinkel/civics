"""
Day 3 Track B — BPS Packet Checker

Tests whether the model can act as a BPS school registration packet assistant:
given a set of family documents, assess whether the packet satisfies all four
BPS registration requirements, detect the duplicate-category rule violation if
triggered, and produce a plain-language summary of what to bring and what to replace.

Example:
  cd spike/scripts/day3
  python day3_track_b.py --scenarios B1,B2 --runs 1
  python day3_track_b.py  # all 8 scenarios
"""

from __future__ import annotations

import argparse
import base64
import io
import json
import sys
import time
from pathlib import Path

import httpx
import ollama

SCRIPT_DIR = Path(__file__).resolve().parent
SPIKE_DIR = SCRIPT_DIR.parent.parent.parent
DEGRADED_DIR = SPIKE_DIR / "artifacts" / "degraded"

# Model configuration
DEFAULT_MODEL = "gemma4:e4b"
DEFAULT_TEMP = 0.0

# Track B scenarios from DAY3_PLAN.md
# Each scenario: (scenario_id, [artifact_ids], document_descriptions, gold_answers)
SCENARIOS = {
    "B1": {
        "artifacts": ["D12", "D05", "D06", "D13"],
        "descriptions": [
            "Document 1: birth certificate (D12)",
            "Document 2: lease agreement (D05)",
            "Document 3: utility bill (D06)",
            "Document 4: immunization record (D13)",
        ],
        "gold": {
            "requirements": [
                {"requirement": "proof_of_age", "status": "satisfied", "matched_document": "D12"},
                {"requirement": "residency_proof_1", "status": "satisfied", "matched_document": "D05"},
                {"requirement": "residency_proof_2", "status": "satisfied", "matched_document": "D06"},
                {"requirement": "immunization_record", "status": "satisfied", "matched_document": "D13"},
            ],
            "duplicate_category_flag": False,
        },
        "tests": "Complete packet with two different residency categories (lease + utility bill)",
    },
    "B2": {
        "artifacts": ["D12", "D05", "D06"],
        "descriptions": [
            "Document 1: birth certificate (D12)",
            "Document 2: lease agreement (D05)",
            "Document 3: utility bill (D06)",
        ],
        "gold": {
            "requirements": [
                {"requirement": "proof_of_age", "status": "satisfied", "matched_document": "D12"},
                {"requirement": "residency_proof_1", "status": "satisfied", "matched_document": "D05"},
                {"requirement": "residency_proof_2", "status": "satisfied", "matched_document": "D06"},
                {"requirement": "immunization_record", "status": "missing", "matched_document": "MISSING"},
            ],
            "duplicate_category_flag": False,
        },
        "tests": "Missing immunization record detection",
    },
    "B3": {
        "artifacts": ["D12", "D05", "D06", "D13"],
        "descriptions": [
            "Document 1: birth certificate (D12)",
            "Document 2: lease agreement (D05)",
            "Document 3: utility bill (D06)",
            "Document 4: immunization record (D13 - check for MMR)",
        ],
        "gold": {
            "requirements": [
                {"requirement": "proof_of_age", "status": "satisfied", "matched_document": "D12"},
                {"requirement": "residency_proof_1", "status": "satisfied", "matched_document": "D05"},
                {"requirement": "residency_proof_2", "status": "satisfied", "matched_document": "D06"},
                {"requirement": "immunization_record", "status": "questionable", "notes": "MMR vaccine not present in record"},
            ],
            "duplicate_category_flag": False,
        },
        "tests": "Missing MMR vaccine detection (immunization record present but incomplete)",
        "note": "Uses D13 which has all vaccines; if D13b variant exists, use that instead",
    },
    "B4": {
        "artifacts": ["D12", "D05", "D14", "D13"],
        "descriptions": [
            "Document 1: birth certificate (D12)",
            "Document 2: lease agreement (D05)",
            "Document 3: second lease agreement (D14)",
            "Document 4: immunization record (D13)",
        ],
        "gold": {
            "requirements": [
                {"requirement": "proof_of_age", "status": "satisfied", "matched_document": "D12"},
                {"requirement": "residency_proof_1", "status": "satisfied", "matched_document": "D05"},
                {"requirement": "residency_proof_2", "status": "missing", "notes": "D14 is same category as D05 — does not count as second proof"},
                {"requirement": "immunization_record", "status": "satisfied", "matched_document": "D13"},
            ],
            "duplicate_category_flag": True,
            "duplicate_category_explanation": "same_residency_category_duplicate",
        },
        "tests": "Duplicate residency category detection (two leases = one category)",
    },
    "B5": {
        "artifacts": ["D12", "D15", "D16", "D13"],
        "descriptions": [
            "Document 1: birth certificate (D12)",
            "Document 2: notarized affidavit (D15)",
            "Document 3: utility bill in Spanish (D16)",
            "Document 4: immunization record (D13)",
        ],
        "gold": {
            "requirements": [
                {"requirement": "proof_of_age", "status": "satisfied", "matched_document": "D12"},
                {"requirement": "residency_proof_1", "status": "satisfied", "matched_document": "D15"},
                {"requirement": "residency_proof_2", "status": "satisfied", "matched_document": "D16"},
                {"requirement": "immunization_record", "status": "satisfied", "matched_document": "D13"},
            ],
            "duplicate_category_flag": False,
        },
        "tests": "Multilingual document handling (Spanish utility bill)",
    },
    "B6": {
        "artifacts": ["D12", "D05", "D15", "D13"],
        "descriptions": [
            "Document 1: birth certificate (D12)",
            "Document 2: lease agreement (D05)",
            "Document 3: notarized host family affidavit (D15)",
            "Document 4: immunization record (D13)",
        ],
        "gold": {
            "requirements": [
                {"requirement": "proof_of_age", "status": "satisfied", "matched_document": "D12"},
                {"requirement": "residency_proof_1", "status": "satisfied", "matched_document": "D05"},
                {"requirement": "residency_proof_2", "status": "satisfied", "matched_document": "D15"},
                {"requirement": "immunization_record", "status": "satisfied", "matched_document": "D13"},
            ],
            "duplicate_category_flag": False,
        },
        "tests": "Notarized affidavit as valid second residency category",
    },
    "B7": {
        "artifacts": ["D12", "D05", "D07", "D13"],
        "descriptions": [
            "Document 1: birth certificate (D12)",
            "Document 2: lease agreement (D05)",
            "Document 3: cell phone bill (D07)",
            "Document 4: immunization record (D13)",
        ],
        "gold": {
            "requirements": [
                {"requirement": "proof_of_age", "status": "satisfied", "matched_document": "D12"},
                {"requirement": "residency_proof_1", "status": "satisfied", "matched_document": "D05"},
                {"requirement": "residency_proof_2", "status": "questionable", "matched_document": "D07", "notes": "phone bill acceptance varies by BPS policy"},
                {"requirement": "immunization_record", "status": "satisfied", "matched_document": "D13"},
            ],
            "duplicate_category_flag": False,
        },
        "tests": "Phone bill ambiguity (should be questionable, not satisfied)",
    },
    "B8": {
        "artifacts": ["D09"],
        "descriptions": [
            "Document 1: state ID (D09)",
        ],
        "gold": {
            "requirements": [
                {"requirement": "proof_of_age", "status": "missing", "notes": "state ID is not accepted as BPS age proof — need birth certificate or passport"},
                {"requirement": "residency_proof_1", "status": "missing", "matched_document": "MISSING"},
                {"requirement": "residency_proof_2", "status": "missing", "matched_document": "MISSING"},
                {"requirement": "immunization_record", "status": "missing", "matched_document": "MISSING"},
            ],
            "duplicate_category_flag": False,
        },
        "tests": "Completely empty packet detection (state ID is not age proof for BPS)",
    },
}

BPS_PROMPT_TEMPLATE = """You are helping a family prepare their Boston Public Schools registration packet.

The BPS registration checklist requires:
- Proof of child's age (birth certificate or passport)
- TWO proofs of Boston residency from DIFFERENT categories.
  Valid categories: lease/deed, utility bill, bank statement,
  government mail, employer letter, notarized affidavit.
  Two documents from the same category count as only ONE proof.
- Current immunization record
- Grade-level indicator (most recent report card or transcript,
  if applicable)

CRITICAL: If a document is blurry, unreadable, or you cannot verify
its contents, you MUST set status to "questionable" (not "satisfied")
and explain why in the notes field. Never guess about document content.

Important policy notes:
- If both residency documents are leases or deeds, set
  duplicate_category_flag to true and return
  "same_residency_category_duplicate" in duplicate_category_explanation.
- If a document is a phone bill or cell phone statement, its residency
  status is policy-dependent — set status to "questionable" and note
  this in the notes field.
- If ANY required document is missing, set status to "missing" and
  matched_document to "MISSING".

The family has uploaded the following documents (images attached):
{DOCUMENT_LIST}

Return JSON:
{{
  "requirements": [
    {{
      "requirement": "",
      "status": "satisfied|questionable|missing",
      "confidence": "high|medium|low",
      "confidence_score": 0.0,
      "matched_document": "[document name or MISSING]",
      "evidence": "[quote or observation]",
      "notes": ""
    }}
  ],
  "duplicate_category_flag": true|false,
  "duplicate_category_explanation": "",
  "family_summary": "[plain language: what to bring, what to replace]"
}}

Confidence guidelines:
- "high" / 0.8-1.0: You can clearly read the document and it unambiguously meets requirements
- "medium" / 0.5-0.7: The document appears valid but has some issues (e.g., policy-dependent acceptance)
- "low" / 0.0-0.4: Document is unclear, partially unreadable, or you are uncertain

When confidence is "low", status MUST be "questionable" or "missing".

Important: never state that the packet guarantees registration
or school assignment.

Return ONLY valid JSON. No markdown, no explanation.
"""


def to_jpeg_b64(path: Path, *, pdf_dpi: int = 100, jpeg_quality: int = 90) -> str:
    """Convert image/PDF to base64 JPEG."""
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
    """Parse model response with retry logic for E4B quirks."""
    # First attempt
    result = _parse_json(raw)
    if result:
        return result
    # Try wrapping bare key:value output (E4B occasionally omits braces)
    try:
        return json.loads("{" + raw.strip() + "}")
    except Exception:
        return None


def _parse_json(raw: str) -> dict | None:
    """Parse JSON response, handling markdown fences."""
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
        return None


def resolve_artifact_path(aid: str, variant: str = "degraded") -> Path | None:
    """Resolve artifact path."""
    if variant == "degraded":
        p = DEGRADED_DIR / f"{aid}-degraded.jpg"
        return p if p.exists() else None
    return None


def check_d13b_exists() -> bool:
    """Check if D13b variant (MMR missing) exists."""
    p = DEGRADED_DIR / "D13b-degraded.jpg"
    return p.exists()


def normalize_requirement_name(req_name: str) -> str:
    """Normalize requirement name for semantic matching.

    Maps model's full requirement descriptions to gold requirement keys.
    """
    req_lower = str(req_name).lower().strip()

    # Proof of age
    if any(term in req_lower for term in ["age", "birth", "passport", "child's age"]):
        return "proof_of_age"

    # Residency proof 1 (first residency proof)
    if any(term in req_lower for term in ["residency", "residence", "address"]):
        # Check if it's the "TWO proofs" combined requirement vs individual
        if "two proofs" in req_lower or "different categories" in req_lower:
            return "residency_combined"  # Special handling for combined requirement
        # Individual residency proofs - check context in matching logic
        return "residency_proof"

    # Immunization
    if any(term in req_lower for term in ["immunization", "vaccine", "mmr"]):
        return "immunization_record"

    # Grade level
    if any(term in req_lower for term in ["grade", "report card", "transcript", "school record"]):
        return "grade_level_indicator"

    return req_lower.replace(" ", "_")


def extract_document_id(matched_doc: str) -> str | None:
    """Extract document ID (e.g., D12) from matched_document string.

    Handles formats like:
    - "D12"
    - "Document 1: birth certificate"
    - "Document 2: lease agreement (D05)"
    - "Document 1: birth certificate (D12)"
    """
    if not matched_doc:
        return None

    doc_upper = str(matched_doc).upper().strip()

    # Direct ID match (D01-D99)
    import re
    id_match = re.search(r'\b(D\d{1,2})\b', doc_upper)
    if id_match:
        return id_match.group(1)

    return None


def score_requirement_status(extracted: str | None, expected: str) -> dict:
    """Score requirement status field."""
    if extracted is None:
        return {"score": 0, "label": "missing", "note": "null response"}

    ext = str(extracted).strip().lower()
    exp = expected.strip().lower()

    if ext == exp:
        return {"score": 2, "label": "exact", "note": ""}

    # Right category wrong label
    status_order = {"satisfied": 2, "questionable": 1, "missing": 0}
    exp_level = status_order.get(exp, 1)
    ext_level = status_order.get(ext, 1)

    if abs(exp_level - ext_level) <= 1 and exp_level != ext_level:
        return {"score": 1, "label": "partial", "note": f"expected '{expected}', got '{extracted}'"}

    return {"score": -1, "label": "wrong", "note": f"expected '{expected}', got '{extracted}'"}


def score_matched_document(extracted: str | None, expected: str) -> dict:
    """Score matched_document field with document ID extraction."""
    if extracted is None:
        return {"score": 0, "label": "missing", "note": "null response"}

    exp = expected.strip().upper()

    # Extract document ID from the extracted string
    extracted_id = extract_document_id(extracted)

    if extracted_id:
        if extracted_id == exp:
            return {"score": 2, "label": "exact", "note": ""}
        # Partial credit if we extracted some ID but it's wrong
        return {"score": 1, "label": "partial", "note": f"expected '{expected}', got '{extracted_id}'"}

    # No ID found, try string matching as fallback
    ext = str(extracted).strip().upper()
    if exp in ext or ext in exp:
        return {"score": 1, "label": "partial", "note": f"expected '{expected}', got '{extracted}'"}

    return {"score": -1, "label": "wrong", "note": f"expected '{expected}', got '{extracted}'"}


def run_scenario(
    client: ollama.Client,
    scenario_id: str,
    scenario: dict,
    model: str,
    temperature: float,
    pdf_dpi: int,
    jpeg_quality: int,
) -> dict:
    """Run a single scenario and return result record."""
    # Check for D13b variant for B3
    artifact_ids = scenario["artifacts"].copy()
    if scenario_id == "B3" and check_d13b_exists():
        # Replace D13 with D13b for MMR-missing test
        artifact_ids = ["D13b" if aid == "D13" else aid for aid in artifact_ids]

    # Load all document images
    images_b64 = []
    for aid in artifact_ids:
        path = resolve_artifact_path(aid)
        if path is None:
            print(f"  Warning: {aid} not found, skipping scenario {scenario_id}", file=sys.stderr)
            return {
                "scenario_id": scenario_id,
                "error": f"Artifact {aid} not found",
                "skipped": True,
            }
        b64 = to_jpeg_b64(path, pdf_dpi=pdf_dpi, jpeg_quality=jpeg_quality)
        images_b64.append(b64)

    # Build prompt
    doc_list = "\n".join(scenario["descriptions"])
    prompt = BPS_PROMPT_TEMPLATE.format(DOCUMENT_LIST=doc_list)

    # Run inference
    t0 = time.time()
    r = client.chat(
        model=model,
        messages=[{"role": "user", "content": prompt, "images": images_b64}],
        options={"temperature": temperature},
    )
    elapsed = time.time() - t0
    raw = r.get("message", {}).get("content") or ""

    # Parse response
    parsed = parse_response(raw)

    # Score results
    scores = {
        "requirements": [],
        "missing_item_detected": None,
        "duplicate_flag_correct": None,
        "abstention_correct": None,
    }
    critical_flags = []

    if parsed:
        requirements = parsed.get("requirements", [])
        gold_reqs_list = scenario["gold"]["requirements"]

        # Build lookup with normalized keys
        gold_reqs = {}
        for r in gold_reqs_list:
            key = r["requirement"]
            gold_reqs[key] = r
            # Also add normalized version for flexible matching
            norm_key = normalize_requirement_name(key)
            if norm_key != key:
                gold_reqs[norm_key] = r

        # Track which gold requirements we've matched
        matched_gold = set()

        for req in requirements:
            req_text = req.get("requirement", "")
            req_name = normalize_requirement_name(req_text)

            # Try to find matching gold requirement
            gold_req = gold_reqs.get(req_name, {})

            # For residency proofs, handle the combined vs individual case
            if req_name == "residency_combined":
                # This is the "TWO proofs" combined requirement
                # Score against residency_proof_1 and residency_proof_2 combined
                gold_req_1 = gold_reqs.get("residency_proof_1", {})
                gold_req_2 = gold_reqs.get("residency_proof_2", {})

                # Use the status from the combined requirement
                status_score = score_requirement_status(
                    req.get("status"), "satisfied"  # Combined is satisfied if both are
                )

                # Extract document IDs from the matched_document field
                matched_doc = req.get("matched_document", "")
                doc_ids = extract_document_id(matched_doc)

                # Score based on whether we found the right documents
                # This is a simplified scoring - the model returns combined info
                doc_score = {"score": 1, "label": "partial", "note": "combined residency requirement"}

                scores["requirements"].append({
                    "requirement": req_text,
                    "status_score": status_score["score"],
                    "status_label": status_score["label"],
                    "document_score": doc_score["score"],
                    "document_label": doc_score["label"],
                })
                continue

            # Normal case
            status_score = score_requirement_status(
                req.get("status"), gold_req.get("status", "")
            )
            doc_score = score_matched_document(
                req.get("matched_document"), gold_req.get("matched_document", "MISSING")
            )

            scores["requirements"].append({
                "requirement": req_text,
                "status_score": status_score["score"],
                "status_label": status_score["label"],
                "document_score": doc_score["score"],
                "document_label": doc_score["label"],
            })

        # Check duplicate flag (B4)
        if scenario_id == "B4":
            dup_flag = parsed.get("duplicate_category_flag")
            if dup_flag is True:
                scores["duplicate_flag_correct"] = True
            else:
                scores["duplicate_flag_correct"] = False
                critical_flags.append("CRITICAL: duplicate_category_flag not set for two leases")

        # Check missing item detection (B2, B8)
        if scenario_id in ("B2", "B8"):
            missing_detected = any(
                r.get("status") == "missing" and r.get("matched_document") == "MISSING"
                for r in requirements
            )
            scores["missing_item_detected"] = missing_detected

        # Check abstention (B7) - phone bill should be flagged as questionable
        if scenario_id == "B7":
            phone_bill_questionable = False
            for req in requirements:
                req_text = req.get("requirement", "").lower()
                # Check for combined residency requirement or individual residency proof
                if "residency" in req_text:
                    # Check if phone bill is mentioned with questionable status or in notes
                    matched_doc = str(req.get("matched_document", "")).lower()
                    notes = str(req.get("notes", "")).lower()
                    status = req.get("status", "").lower()
                    confidence = str(req.get("confidence", "")).lower()

                    # Phone bill flagged if: status=questionable, or low confidence, or noted in notes
                    if ("phone" in matched_doc or "cell" in matched_doc):
                        if status == "questionable" or confidence == "low":
                            phone_bill_questionable = True
                        elif "questionable" in notes or "policy" in notes:
                            phone_bill_questionable = True

            scores["abstention_correct"] = phone_bill_questionable
            if not phone_bill_questionable:
                critical_flags.append("WARNING: phone bill not flagged as questionable")

        # Critical checks
        # B4: duplicate flag must be true
        if scenario_id == "B4" and not parsed.get("duplicate_category_flag"):
            critical_flags.append("CRITICAL: duplicate_category_flag false when two leases submitted")

        # B8: no requirement should be satisfied
        if scenario_id == "B8":
            any_satisfied = any(r.get("status") == "satisfied" for r in requirements)
            if any_satisfied:
                critical_flags.append("CRITICAL: requirement marked satisfied when only state ID submitted")

    return {
        "scenario_id": scenario_id,
        "artifact_ids": artifact_ids,
        "variant": "degraded",
        "model": model,
        "temperature": temperature,
        "elapsed_s": round(elapsed, 2),
        "parse_ok": parsed is not None,
        "raw_response": raw,
        "parsed": parsed,
        "scores": scores,
        "critical_flags": critical_flags,
        "tests": scenario["tests"],
    }


def main():
    ap = argparse.ArgumentParser(description="Day 3 Track B — BPS Packet Checker")
    ap.add_argument(
        "--scenarios",
        type=str,
        default="",
        help="Comma-separated scenario IDs (e.g. B1,B2). Default: all 8 scenarios.",
    )
    ap.add_argument("--runs", type=int, default=1, help="Runs per scenario")
    ap.add_argument("--model", type=str, default=DEFAULT_MODEL)
    ap.add_argument("--temp", type=float, default=DEFAULT_TEMP)
    ap.add_argument(
        "--out",
        type=Path,
        default=SCRIPT_DIR / "day3_track_b_results.jsonl",
    )
    ap.add_argument("--append", action="store_true", help="Append to output instead of truncating")
    ap.add_argument("--http-timeout", type=float, default=900.0)
    ap.add_argument("--pdf-dpi", type=int, default=100)
    ap.add_argument("--jpeg-quality", type=int, default=90)
    args = ap.parse_args()

    scenario_ids = (
        [x.strip() for x in args.scenarios.split(",") if x.strip()]
        if args.scenarios
        else list(SCENARIOS.keys())
    )

    timeout = httpx.Timeout(args.http_timeout)
    client = ollama.Client(timeout=timeout)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    out_mode = "a" if args.append else "w"
    n_written = 0

    with args.out.open(out_mode, encoding="utf-8") as out_f:
        for scenario_id in scenario_ids:
            scenario = SCENARIOS.get(scenario_id)
            if not scenario:
                print(f"Unknown scenario: {scenario_id}", file=sys.stderr)
                continue

            print(f"\nRunning scenario {scenario_id}: {scenario['tests']}")

            for run_idx in range(args.runs):
                result = run_scenario(
                    client,
                    scenario_id,
                    scenario,
                    args.model,
                    args.temp,
                    args.pdf_dpi,
                    args.jpeg_quality,
                )
                result["run"] = run_idx

                out_f.write(json.dumps(result, ensure_ascii=False) + "\n")
                out_f.flush()
                n_written += 1

                if result.get("skipped"):
                    print(f"  {scenario_id} run{run_idx} SKIPPED ({result.get('error')})")
                    continue

                label = "ok" if result["parse_ok"] else "parse_fail"
                crit = " [CRITICAL]" if result["critical_flags"] else ""
                print(f"  {scenario_id} run{run_idx} {label} ({result['elapsed_s']:.1f}s){crit}")

                if result["critical_flags"]:
                    for flag in result["critical_flags"]:
                        print(f"    ! {flag}")

    print(f"\nWrote {n_written} records to {args.out}")


if __name__ == "__main__":
    main()

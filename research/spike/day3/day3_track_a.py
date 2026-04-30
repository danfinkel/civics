"""
Day 3 Track A — SNAP Proof-Pack Builder

Tests whether the model can act as a SNAP proof-pack assistant: given a DTA
verification or recertification notice plus a set of resident documents, produce
a structured proof-pack grid identifying which categories are covered, which are
missing, and what action the resident should take — with a plain-language summary.

Usage:
    cd spike/scripts/day3
    python day3_track_a.py
    python day3_track_a.py --scenarios A1,A3  # run specific scenarios only
    python day3_track_a.py --model gemma4:e4b --temp 0.0
"""

from __future__ import annotations

import argparse
import base64
import io
import json
import sys
import time
from pathlib import Path
from typing import Any

import httpx
import ollama
from PIL import Image

SCRIPT_DIR = Path(__file__).resolve().parent
SPIKE_DIR = SCRIPT_DIR.parent.parent  # Go up to research/ (research/spike/day3 -> research/spike -> research)
ARTIFACTS_DIR = SPIKE_DIR / "artifacts"
DEGRADED_DIR = ARTIFACTS_DIR / "degraded"
BLURRY_DIR = ARTIFACTS_DIR / "blurry"

# Import shared utilities from day1
sys.path.insert(0, str(SPIKE_DIR / "spike" / "day1"))
from day1_extract import to_jpeg_b64, score_field  # noqa: E402

MODEL = "gemma4:e4b"
TEMPERATURE = 0.0

PROMPT_TEMPLATE = """You are helping a Massachusetts resident prepare documents for a
SNAP recertification or verification request.

The resident has shared:
1. A government notice (image attached)
2. The following documents they have at home (images attached):
{DOCUMENT_LIST}

Your job:

Step 1: First, assess whether you can clearly read the notice.
- Check if text is legible and dates/numbers are visible
- If ANY text is blurry, smudged, or unreadable, you cannot proceed

CRITICAL ABSTENTION RULE:
If you cannot clearly read the notice text, dates, or categories,
return EXACTLY this for notice_summary:
{{
  "requested_categories": ["UNCERTAIN"],
  "deadline": "UNCERTAIN",
  "consequence": "UNCERTAIN"
}}
Then assess the documents normally but with lower confidence.

Step 2: If the notice is readable, identify what proof categories are
being requested and the response deadline.

Step 3: For each document, classify it and assess whether it
likely satisfies one of the requested categories.

Return JSON:
{{
  "notice_summary": {{
    "requested_categories": [],
    "deadline": "",
    "consequence": ""
  }},
  "proof_pack": [
    {{
      "category": "",
      "matched_document": "[document name or MISSING]",
      "assessment": "likely_satisfies|likely_does_not_satisfy|missing|uncertain",
      "confidence": "high|medium|low",
      "confidence_score": 0.0,
      "evidence": "[quote from document]",
      "caveats": ""
    }}
  ],
  "action_summary": "[one paragraph in plain language for the resident]"
}}

Confidence guidelines:
- "high" / 0.8-1.0: You are certain based on clear evidence
- "medium" / 0.5-0.7: Some ambiguity but likely correct
- "low" / 0.0-0.4: Uncertain, unclear, or incomplete information

When confidence is "low", set assessment to "uncertain".

Remember: If the notice is blurry, return UNCERTAIN. Do not guess."""


# Track A Scenarios
SCENARIOS: dict[str, dict[str, Any]] = {
    "A1": {
        "notice": ("D01", "degraded"),
        "documents": [
            ("D03", "degraded", "pay stub (D03)"),
            ("D06", "degraded", "utility bill (D06)"),
            ("D09", "degraded", "state ID (D09)"),
        ],
        "gold": {
            "notice_summary": {
                "requested_categories": ["earned_income"],
                "deadline": "2026-04-15",
                "consequence": "case_closure"
            },
            "proof_pack": [
                {
                    "category": "earned_income",
                    "matched_document": "D03",
                    "assessment": "likely_satisfies"
                }
            ]
        },
        "description": "Strong match, single category"
    },
    "A2": {
        "notice": ("D01", "degraded"),
        "documents": [
            ("D05", "degraded", "lease agreement (D05)"),
            ("D07", "degraded", "cell phone bill (D07)"),
            ("D08", "degraded", "handwritten note (D08)"),
        ],
        "gold": {
            "proof_pack": [
                {
                    "category": "earned_income",
                    "matched_document": "MISSING",
                    "assessment": "missing"
                }
            ]
        },
        "description": "Ambiguous residency proof included"
    },
    "A3": {
        "notice": ("D01", "degraded"),
        "documents": [
            ("D04", "degraded", "pay stub (D04)"),
        ],
        "gold": {
            "proof_pack": [
                {
                    "category": "earned_income",
                    "matched_document": "D04",
                    "assessment": "likely_does_not_satisfy",
                    "caveats": "[date outside acceptable window]"
                }
            ]
        },
        "description": "Stale pay stub submitted"
    },
    "A4": {
        "notice": ("D02", "degraded"),
        "documents": [
            ("D03", "degraded", "pay stub (D03)"),
            ("D05", "degraded", "lease agreement (D05)"),
            ("D06", "degraded", "utility bill (D06)"),
        ],
        "gold": {
            "notice_summary": {
                "requested_categories": ["earned_income", "residency", "household_expenses"],
                "deadline": "2026-04-22",
                "consequence": "[case consequences]"
            },
            "proof_pack": [
                {"category": "earned_income", "matched_document": "D03", "assessment": "likely_satisfies"},
                {"category": "residency", "matched_document": "D05", "assessment": "likely_satisfies"},
                {"category": "household_expenses", "matched_document": "D06", "assessment": "likely_satisfies"}
            ]
        },
        "description": "Multi-category notice, full coverage"
    },
    "A5": {
        "notice": ("D02", "degraded"),
        "documents": [
            ("D04", "degraded", "pay stub (D04 — stale)"),
            ("D06", "degraded", "utility bill (D06)"),
        ],
        "gold": {
            "proof_pack": [
                {"category": "earned_income", "matched_document": "D04", "assessment": "likely_does_not_satisfy", "caveats": "[stale date]"},
                {"category": "residency", "matched_document": "D06", "assessment": "likely_satisfies"},
                {"category": "household_expenses", "matched_document": "D06", "assessment": "likely_satisfies"}
            ]
        },
        "description": "Multi-category notice, partial coverage"
    },
    "A6": {
        "notice": ("D01", "blurry"),
        "documents": [
            ("D03", "degraded", "pay stub (D03)"),
        ],
        "gold": {
            "notice_summary": {
                "requested_categories": ["UNCERTAIN"],
                "deadline": "UNCERTAIN",
                "consequence": "UNCERTAIN"
            }
        },
        "description": "Abstention scenario (blurry notice)"
    },
    "A7": {
        "notice": ("D01", "degraded"),
        "documents": [
            ("D10", "degraded", "government award letter (D10)"),
        ],
        "gold": {
            "proof_pack": [
                {
                    "category": "earned_income",
                    "matched_document": "D10",
                    "assessment": "likely_does_not_satisfy",
                    "caveats": "[housing assistance is not earned income]"
                }
            ]
        },
        "description": "Award letter submitted as income proof"
    },
    "A8": {
        "notice": ("D01", "degraded"),
        "documents": [
            ("D07", "degraded", "cell phone bill (D07)"),
        ],
        "gold": {
            "proof_pack": [
                {
                    "category": "earned_income",
                    "matched_document": "D07",
                    "assessment": "likely_does_not_satisfy",
                    "caveats": "[phone bill is not income proof]"
                }
            ]
        },
        "description": "Phone bill ambiguity"
    },
}


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
        if cleaned and not cleaned.startswith("{") and not cleaned.startswith("["):
            if '"' in cleaned and ":" in cleaned:
                try:
                    wrapped = "{" + cleaned + "}"
                    return json.loads(wrapped)
                except json.JSONDecodeError:
                    pass

        return None


def parse_with_retry(raw: str) -> dict | None:
    """Parse with retry wrapper as specified in Day 3 plan."""
    # First attempt
    result = parse_response(raw)
    if result:
        return result
    # Try wrapping bare key:value output (E4B occasionally omits braces)
    try:
        return json.loads("{" + raw.strip() + "}")
    except Exception:
        return None


def resolve_artifact_path(aid: str, variant: str) -> Path | None:
    """Resolve artifact path based on ID and variant."""
    if variant == "degraded":
        p = DEGRADED_DIR / f"{aid}-degraded.jpg"
        return p if p.exists() else None
    elif variant == "blurry":
        p = BLURRY_DIR / f"{aid}-blurry.jpg"
        return p if p.exists() else None
    return None


def build_document_list(documents: list[tuple[str, str, str]]) -> str:
    """Build the document list section for the prompt."""
    lines = []
    for i, (_, _, desc) in enumerate(documents, 1):
        lines.append(f"- Document {i}: {desc}")
    return "\n".join(lines)


def load_images_for_scenario(scenario: dict[str, Any]) -> tuple[str | None, list[str]]:
    """Load notice and document images as base64."""
    notice_id, notice_variant = scenario["notice"]
    notice_path = resolve_artifact_path(notice_id, notice_variant)
    if notice_path is None:
        print(f"Warning: Notice file not found for {notice_id}-{notice_variant}", file=sys.stderr)
        return None, []

    notice_b64 = to_jpeg_b64(notice_path, pdf_dpi=100, jpeg_quality=90)

    doc_images_b64 = []
    for doc_id, doc_variant, _ in scenario["documents"]:
        doc_path = resolve_artifact_path(doc_id, doc_variant)
        if doc_path is None:
            print(f"Warning: Document file not found for {doc_id}-{doc_variant}", file=sys.stderr)
            return None, []
        doc_b64 = to_jpeg_b64(doc_path, pdf_dpi=100, jpeg_quality=90)
        doc_images_b64.append(doc_b64)

    return notice_b64, doc_images_b64


def normalize_category(cat: str) -> str:
    """Normalize category name for semantic matching."""
    cat_lower = str(cat).lower().strip()
    # Map common variations to canonical forms
    if any(term in cat_lower for term in ["income", "earned", "pay", "wage", "salary"]):
        return "income"
    if any(term in cat_lower for term in ["residency", "residence", "address", "live"]):
        return "residency"
    if any(term in cat_lower for term in ["expense", "expenses", "household", "bill", "utility"]):
        return "expenses"
    return cat_lower


def score_notice_categories(extracted: list, gold: list) -> dict:
    """Score notice category extraction with semantic matching."""
    if not extracted and not gold:
        return {"score": 2, "label": "exact"}

    # Normalize to semantic categories
    extracted_normalized = set(normalize_category(c) for c in extracted)
    gold_normalized = set(normalize_category(g) for g in gold)

    # Remove empty strings
    extracted_normalized = {c for c in extracted_normalized if c}
    gold_normalized = {c for c in gold_normalized if c}

    # Check for exact match
    if extracted_normalized == gold_normalized:
        return {"score": 2, "label": "exact"}

    # Check for partial match
    overlap = extracted_normalized & gold_normalized
    if overlap:
        return {"score": 1, "label": "partial", "note": f"overlap: {overlap}"}

    return {"score": -1, "label": "wrong", "note": f"expected: {gold}, got: {extracted}"}


def parse_date(date_str: str) -> tuple[int, int, int] | None:
    """Parse various date formats to (year, month, day) tuple."""
    import re
    s = str(date_str).lower().strip()

    # Handle UNCERTAIN
    if s in ["uncertain", "", "null", "none"]:
        return None

    # Try ISO format: 2026-04-15
    iso_match = re.match(r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})', s)
    if iso_match:
        return (int(iso_match.group(1)), int(iso_match.group(2)), int(iso_match.group(3)))

    # Try US format: April 15, 2026 or Apr 15, 2026
    month_names = {
        'jan': 1, 'january': 1, 'feb': 2, 'february': 2, 'mar': 3, 'march': 3,
        'apr': 4, 'april': 4, 'may': 5, 'jun': 6, 'june': 6,
        'jul': 7, 'july': 7, 'aug': 8, 'august': 8, 'sep': 9, 'sept': 9, 'september': 9,
        'oct': 10, 'october': 10, 'nov': 11, 'november': 11, 'dec': 12, 'december': 12
    }
    us_match = re.match(r'([a-z]+)[\s\.]+(\d{1,2})[\s,]*(\d{4})', s)
    if us_match:
        month_str = us_match.group(1)
        month = month_names.get(month_str)
        if month:
            return (int(us_match.group(3)), month, int(us_match.group(2)))

    return None


def score_deadline(extracted: str, gold: str) -> dict:
    """Score deadline extraction with date parsing."""
    if not extracted:
        return {"score": 0, "label": "missing"}

    # Handle UNCERTAIN case
    if str(gold).upper() == "UNCERTAIN":
        if str(extracted).upper() in ["UNCERTAIN", ""]:
            return {"score": 2, "label": "exact"}
        return {"score": -1, "label": "wrong", "note": f"expected UNCERTAIN, got: {extracted}"}

    extracted_date = parse_date(extracted)
    gold_date = parse_date(gold)

    if extracted_date is None or gold_date is None:
        # Fall back to string matching
        extracted_norm = str(extracted).lower().strip().replace("-", "/")
        gold_norm = str(gold).lower().strip().replace("-", "/")
        if extracted_norm == gold_norm:
            return {"score": 2, "label": "exact"}
        if gold_norm in extracted_norm or extracted_norm in gold_norm:
            return {"score": 1, "label": "partial"}
        return {"score": -1, "label": "wrong", "note": f"expected: {gold}, got: {extracted}"}

    if extracted_date == gold_date:
        return {"score": 2, "label": "exact"}

    # Partial credit for same month/year
    if extracted_date[0] == gold_date[0] and extracted_date[1] == gold_date[1]:
        return {"score": 1, "label": "partial", "note": "same month/year"}

    return {"score": -1, "label": "wrong", "note": f"expected: {gold}, got: {extracted}"}


def score_consequence(extracted: str, gold: str) -> dict:
    """Score consequence extraction."""
    if not extracted:
        return {"score": 0, "label": "missing"}

    extracted_lower = str(extracted).lower().strip()
    gold_lower = str(gold).lower().strip()

    if gold_lower in extracted_lower or extracted_lower in gold_lower:
        return {"score": 2, "label": "exact"}

    # Partial credit for related terms
    if "closure" in extracted_lower or "close" in extracted_lower:
        return {"score": 1, "label": "partial"}

    return {"score": 0, "label": "abstain"}


def score_assessment(extracted: str, gold: str) -> dict:
    """Score proof pack assessment label."""
    if not extracted:
        return {"score": 0, "label": "missing"}

    extracted_lower = str(extracted).lower().strip()
    gold_lower = str(gold).lower().strip()

    if extracted_lower == gold_lower:
        return {"score": 2, "label": "exact"}

    # Right valence, wrong label
    positive_labels = ["likely_satisfies", "satisfied"]
    negative_labels = ["likely_does_not_satisfy", "missing", "does_not_satisfy"]

    extracted_positive = any(p in extracted_lower for p in positive_labels)
    gold_positive = any(p in gold_lower for p in positive_labels)
    extracted_negative = any(n in extracted_lower for n in negative_labels)
    gold_negative = any(n in gold_lower for n in negative_labels)

    if (extracted_positive and gold_positive) or (extracted_negative and gold_negative):
        return {"score": 1, "label": "right_valence"}

    return {"score": -1, "label": "wrong_valence", "note": f"expected: {gold}, got: {extracted}"}


def score_matched_document(extracted: str, gold: str) -> dict:
    """Score matched document identification."""
    if not extracted:
        return {"score": 0, "label": "missing"}

    extracted_upper = str(extracted).upper().strip()
    gold_upper = str(gold).upper().strip()

    if extracted_upper == gold_upper:
        return {"score": 2, "label": "exact"}

    # Check if document ID is contained
    if gold_upper in extracted_upper or extracted_upper in gold_upper:
        return {"score": 1, "label": "partial"}

    return {"score": -1, "label": "wrong", "note": f"expected: {gold}, got: {extracted}"}


def score_proof_pack(extracted_pack: list[dict], gold_pack: list[dict]) -> list[dict]:
    """Score proof pack entries with semantic category matching."""
    scores = []

    # Build lookup by normalized category
    extracted_by_cat: dict[str, dict] = {}
    for p in extracted_pack:
        cat = normalize_category(p.get("category", ""))
        if cat:
            extracted_by_cat[cat] = p

    for gold_entry in gold_pack:
        gold_cat = normalize_category(gold_entry.get("category", ""))
        extracted_entry = extracted_by_cat.get(gold_cat, {})

        entry_scores = {
            "category": gold_entry.get("category", ""),
            "assessment": score_assessment(
                extracted_entry.get("assessment", ""),
                gold_entry.get("assessment", "")
            ),
            "matched_document": score_matched_document(
                extracted_entry.get("matched_document", ""),
                gold_entry.get("matched_document", "")
            )
        }

        # Score caveats if present in gold
        if "caveats" in gold_entry:
            entry_scores["caveats"] = {
                "expected": gold_entry["caveats"],
                "extracted": extracted_entry.get("caveats", "")
            }

        scores.append(entry_scores)

    return scores


def run_scenario(
    client: ollama.Client,
    scenario_id: str,
    scenario: dict[str, Any],
    model: str,
    temperature: float,
) -> dict:
    """Run a single scenario and return results."""
    print(f"\nRunning scenario {scenario_id}: {scenario['description']}")

    # Load images
    notice_b64, doc_images_b64 = load_images_for_scenario(scenario)
    if notice_b64 is None:
        return {
            "scenario_id": scenario_id,
            "error": "Failed to load notice image",
            "parse_ok": False
        }

    # Build prompt
    doc_list = build_document_list(scenario["documents"])
    prompt = PROMPT_TEMPLATE.format(DOCUMENT_LIST=doc_list)

    # Build artifact IDs list
    notice_id, _ = scenario["notice"]
    doc_ids = [d[0] for d in scenario["documents"]]
    artifact_ids = [notice_id] + doc_ids

    # Determine variant (use "blurry" if any document is blurry, else "degraded")
    variants = set([scenario["notice"][1]] + [d[1] for d in scenario["documents"]])
    variant = "blurry" if "blurry" in variants else "degraded"

    # Run inference
    t0 = time.time()
    try:
        r = client.chat(
            model=model,
            messages=[{
                "role": "user",
                "content": prompt,
                "images": [notice_b64] + doc_images_b64
            }],
            options={"temperature": temperature},
        )
        elapsed = time.time() - t0
        raw = r.get("message", {}).get("content") or ""
    except Exception as e:
        return {
            "scenario_id": scenario_id,
            "artifact_ids": artifact_ids,
            "variant": variant,
            "error": str(e),
            "parse_ok": False
        }

    # Parse response
    parsed = parse_with_retry(raw)

    # Score results
    scores = {}
    critical_flags = []

    if parsed:
        gold = scenario["gold"]

        # Score notice summary if present in gold
        if "notice_summary" in gold:
            notice_parsed = parsed.get("notice_summary", {})
            notice_gold = gold["notice_summary"]

            if "requested_categories" in notice_gold:
                scores["notice_categories"] = score_notice_categories(
                    notice_parsed.get("requested_categories", []),
                    notice_gold["requested_categories"]
                )

            if "deadline" in notice_gold:
                scores["deadline"] = score_deadline(
                    notice_parsed.get("deadline", ""),
                    notice_gold["deadline"]
                )

            if "consequence" in notice_gold:
                scores["consequence"] = score_consequence(
                    notice_parsed.get("consequence", ""),
                    notice_gold["consequence"]
                )

        # Score proof pack
        if "proof_pack" in gold:
            proof_parsed = parsed.get("proof_pack", [])
            proof_gold = gold["proof_pack"]
            scores["proof_pack_assessments"] = score_proof_pack(proof_parsed, proof_gold)

            # Check for missing item detection
            gold_missing = any(
                str(p.get("assessment", "")).lower() in ["missing", "uncertain"]
                for p in proof_gold
            )
            if gold_missing:
                detected_missing = any(
                    str(p.get("assessment", "")).lower() in ["missing", "uncertain"]
                    for p in proof_parsed
                )
                scores["missing_item_detected"] = detected_missing

        # Check for abstention (A6) - blurry notice
        if scenario_id == "A6":
            notice_parsed = parsed.get("notice_summary", {})
            categories = notice_parsed.get("requested_categories", [])
            deadline = notice_parsed.get("deadline", "")
            consequence = notice_parsed.get("consequence", "")

            # Check for explicit UNCERTAIN values
            is_abstained = (
                (not categories or "UNCERTAIN" in str(categories).upper()) and
                (not deadline or "UNCERTAIN" in str(deadline).upper()) and
                (not consequence or "UNCERTAIN" in str(consequence).upper())
            )

            # Also check for low confidence in proof pack entries
            if not is_abstained:
                proof_pack = parsed.get("proof_pack", [])
                low_confidence_count = sum(
                    1 for entry in proof_pack
                    if str(entry.get("confidence", "")).lower() == "low" or
                    (isinstance(entry.get("confidence_score"), (int, float)) and entry.get("confidence_score", 1.0) < 0.5)
                )
                if low_confidence_count > 0:
                    scores["low_confidence_detected"] = low_confidence_count

            scores["abstention_correct"] = is_abstained

        # Critical false positive checks
        # A7: model accepts D10 award letter as earned income
        if scenario_id == "A7":
            proof_pack = parsed.get("proof_pack", [])
            for entry in proof_pack:
                if (str(entry.get("matched_document", "")).upper() == "D10" and
                    str(entry.get("assessment", "")).lower() == "likely_satisfies"):
                    critical_flags.append("CRITICAL: A7 - D10 award letter accepted as earned income")

        # A2: model assigns D08 handwritten note as likely_satisfies
        if scenario_id == "A2":
            proof_pack = parsed.get("proof_pack", [])
            for entry in proof_pack:
                if (str(entry.get("matched_document", "")).upper() == "D08" and
                    str(entry.get("assessment", "")).lower() == "likely_satisfies"):
                    critical_flags.append("CRITICAL: A2 - D08 handwritten note marked as likely_satisfies")

        # A3: model accepts D04 stale pay stub without date caveat
        if scenario_id == "A3":
            proof_pack = parsed.get("proof_pack", [])
            for entry in proof_pack:
                if (str(entry.get("matched_document", "")).upper() == "D04" and
                    str(entry.get("assessment", "")).lower() == "likely_satisfies"):
                    caveats = str(entry.get("caveats", "")).lower()
                    if "date" not in caveats and "stale" not in caveats and "old" not in caveats:
                        critical_flags.append("CRITICAL: A3 - D04 stale pay stub accepted without date caveat")

    return {
        "scenario_id": scenario_id,
        "artifact_ids": artifact_ids,
        "variant": variant,
        "model": model,
        "temperature": temperature,
        "elapsed_s": round(elapsed, 2),
        "parse_ok": parsed is not None,
        "raw_response": raw,
        "parsed": parsed,
        "scores": scores,
        "critical_flags": critical_flags
    }


def main():
    ap = argparse.ArgumentParser(description="Day 3 Track A — SNAP Proof-Pack Builder")
    ap.add_argument("--scenarios", type=str, default="",
                    help="Comma-separated scenario IDs to run (default: all)")
    ap.add_argument("--model", type=str, default=MODEL)
    ap.add_argument("--temp", type=float, default=TEMPERATURE)
    ap.add_argument("--out", type=Path, default=SCRIPT_DIR / "day3_track_a_results.jsonl")
    ap.add_argument("--http-timeout", type=float, default=900.0,
                    help="Ollama HTTP client read timeout in seconds")
    ap.add_argument("--pdf-dpi", type=int, default=100, help="Rasterize PDF at this DPI")
    ap.add_argument("--jpeg-quality", type=int, default=90, help="JPEG quality 1-95")
    args = ap.parse_args()

    # Determine which scenarios to run
    if args.scenarios:
        scenario_ids = [s.strip() for s in args.scenarios.split(",") if s.strip()]
    else:
        scenario_ids = list(SCENARIOS.keys())

    # Validate scenario IDs
    for sid in scenario_ids:
        if sid not in SCENARIOS:
            print(f"Error: Unknown scenario '{sid}'", file=sys.stderr)
            sys.exit(1)

    # Initialize Ollama client
    timeout = httpx.Timeout(args.http_timeout)
    client = ollama.Client(timeout=timeout)

    # Run scenarios
    results = []
    for sid in scenario_ids:
        scenario = SCENARIOS[sid]
        result = run_scenario(
            client=client,
            scenario_id=sid,
            scenario=scenario,
            model=args.model,
            temperature=args.temp
        )
        results.append(result)

        # Print summary
        status = "✓" if result.get("parse_ok") else "✗"
        print(f"  {status} Scenario {sid} complete ({result.get('elapsed_s', 0):.1f}s)")
        if result.get("critical_flags"):
            for flag in result["critical_flags"]:
                print(f"  ⚠️  {flag}")

    # Write results
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", encoding="utf-8") as f:
        for result in results:
            f.write(json.dumps(result, ensure_ascii=False) + "\n")

    print(f"\nWrote {len(results)} results to {args.out}")

    # Print summary
    print("\n--- Track A Summary ---")
    total = len(results)
    parsed = sum(1 for r in results if r.get("parse_ok"))
    critical = sum(len(r.get("critical_flags", [])) for r in results)
    print(f"Scenarios run: {total}")
    print(f"Parse OK: {parsed}/{total}")
    print(f"Critical flags: {critical}")


if __name__ == "__main__":
    main()

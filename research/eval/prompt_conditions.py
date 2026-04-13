"""
Version-controlled prompt templates for the Week 3 prompt ablation (D01).

Cite as: civics/research/eval/prompt_conditions.py (PROMPT_ABLATION_VERSION).

Hypothesis: semantically precise field naming reduces hallucination on degraded/blurry
civic notices more than model-size scaling; Conditions A/B/C are all E2B on-device.

Condition A — generic (spike-style keys associated with A6 failure).
Condition B — semantic production-style keys + instructions.
Condition C — same extraction text as B; notice-first preview is implemented on-device
(see InferenceService.inferRawWithNoticePreview + PromptTemplates.trackANoticePreviewOnly).
"""

from __future__ import annotations

# Bump when prompt strings change (paper methods section).
PROMPT_ABLATION_VERSION = "2026-04-11"

# JSON keys emitted by the model under each condition (for scoring / abstention).
GENERIC_FIELD_KEYS: tuple[str, ...] = (
    "document_type",
    "holder_name",
    "key_date",
    "secondary_date",
    "key_amount_or_address",
    "any_id_or_case_number",
)

SEMANTIC_FIELD_KEYS_D01: tuple[str, ...] = (
    "notice_date",
    "response_deadline",
    "requested_category",
    "consequence",
    "caseworker_name",
    "case_number",
    "recipient_name",
)

# Map generic JSON keys → ground_truth.csv field_name for D01 (when both exist).
GENERIC_TO_GT_D01: dict[str, str] = {
    "key_date": "response_deadline",
    "secondary_date": "notice_date",
    "holder_name": "recipient_name",
    "any_id_or_case_number": "case_number",
    "document_type": "requested_category",
    "key_amount_or_address": "office_address",
}


def build_prompt_generic() -> str:
    """Condition A: spike baseline schema + UNREADABLE abstention instruction."""
    keys_block = "\n".join([f'  "{k}": "",' for k in GENERIC_FIELD_KEYS])
    return f"""You are a document analysis assistant. Read the document carefully.

Extract information into the JSON object below. Use only information visible in the document.

Return ONLY valid JSON with exactly these keys. No markdown fences, no commentary.

{{
{keys_block}
}}

For any field you cannot read clearly, set its value to UNREADABLE.
"""


def build_prompt_semantic() -> str:
    """Condition B: production-style semantic keys + date disambiguation (D01 extraction)."""
    keys_block = "\n".join([f'  "{k}": "",' for k in SEMANTIC_FIELD_KEYS_D01])
    return f"""You are a document analysis assistant for a Massachusetts civic benefits notice.

Rules:
- Extract only values clearly present in the document.
- Read each field from its labeled location in the notice.
- For date fields: use semantic labels as requested in the JSON keys (e.g. notice_date vs response_deadline). Do not swap due dates with notice dates.
- Copy names character-by-character as printed.
- If you cannot read a field, set its value to UNREADABLE.
- Return ONLY valid JSON with exactly these keys. No markdown.

{{
{keys_block}
}}
"""


def build_extraction_prompt(prompt_condition: str) -> str:
    """User message body for /infer (OCR is appended on device; C adds preview server-side)."""
    if prompt_condition == "generic":
        return build_prompt_generic()
    if prompt_condition in ("semantic", "semantic-preview"):
        return build_prompt_semantic()
    raise ValueError(f"Unknown prompt_condition: {prompt_condition!r}")


def critical_deadline_key(prompt_condition: str) -> str:
    return "key_date" if prompt_condition == "generic" else "response_deadline"


def field_keys_for_condition(prompt_condition: str) -> tuple[str, ...]:
    if prompt_condition == "generic":
        return GENERIC_FIELD_KEYS
    if prompt_condition in ("semantic", "semantic-preview"):
        return SEMANTIC_FIELD_KEYS_D01
    raise ValueError(f"Unknown prompt_condition: {prompt_condition!r}")

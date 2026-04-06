"""
Prompt templates for CivicLens Track A and Track B.

These prompts are based on the spike findings and optimized for Gemma 4 E4B.
"""

TRACK_A_PROMPT_TEMPLATE = """You are helping a Massachusetts resident prepare documents for a SNAP recertification or verification request.

The resident has shared:
1. A government notice (image attached)
2. The following documents they have at home (images attached):
{DOCUMENT_LIST}

Your job:

Step 1: Read the notice and identify what proof categories are being requested and the response deadline.

Step 2: For each document, classify it and assess whether it likely satisfies one of the requested categories.

Step 3: Return a structured JSON result:

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
      "evidence": "[quote from document]",
      "caveats": ""
    }}
  ],
  "action_summary": "[one paragraph in plain language for the resident]"
}}

Important: never state or imply that a document is accepted by the agency. Use 'appears to satisfy' and 'likely matches' only.
Always show caveats when confidence is not high.
If the notice image is blurry or you cannot clearly read the text, set notice_summary fields to "UNCERTAIN" — do not guess.

Return ONLY valid JSON. No markdown, no explanation.
"""

TRACK_B_PROMPT_TEMPLATE = """You are helping a family prepare their Boston Public Schools registration packet.

The BPS registration checklist requires:
- Proof of child's age (birth certificate or passport)
- TWO proofs of Boston residency from DIFFERENT categories.
  Valid categories: lease/deed, utility bill, bank statement,
  government mail, employer letter, notarized affidavit.
  Two documents from the same category count as only ONE proof.
  If both documents are leases, set duplicate_category_flag to true.
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


def build_track_a_prompt(document_labels: list[str]) -> str:
    """Build the Track A prompt with document list substituted."""
    doc_list = "\n".join(f"{i+1}. {label}" for i, label in enumerate(document_labels))
    return TRACK_A_PROMPT_TEMPLATE.format(DOCUMENT_LIST=doc_list)


def build_track_b_prompt(document_labels: list[str]) -> str:
    """Build the Track B prompt with document list substituted."""
    doc_list = "\n".join(f"Document {i+1}: {label}" for i, label in enumerate(document_labels))
    return TRACK_B_PROMPT_TEMPLATE.format(DOCUMENT_LIST=doc_list)

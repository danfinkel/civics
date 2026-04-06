# Day 3 Execution Plan
## Track-Specific Matching Logic — End-to-End Scenarios

**Spike reference:** Part 3, Section 3.4 (Day 3)  
**Model:** `gemma4:e4b`  
**Temperature:** `0.0`  
**Date:** April 2026

---

## Overview

Day 3 is the first full end-to-end pipeline test. Days 1 and 2 tested individual capabilities in isolation. Day 3 combines them: the model receives a multi-document set and must read a notice or checklist, classify each uploaded document, assess whether each satisfies the relevant proof category, and produce both a structured JSON result and a plain-language resident summary — all in a single inference call.

**The two tracks are completely independent.** Assign each to a separate agent. They share no artifacts, no prompts, no scoring logic, and no dependencies on each other. Both can run simultaneously.

---

## Track Assignment

| Track | Agent | Spike Reference | Script to Build | Artifacts Used |
|-------|-------|----------------|----------------|----------------|
| **Track A** | Agent A | Section 3.4, Track A prompt | `day3_track_a.py` | D01, D02, D03, D04, D05, D06, D07, D08, D09, D10 |
| **Track B** | Agent B | Section 3.4, Track B prompt | `day3_track_b.py` | D05, D06, D09, D11, D12, D13, D14, D15, D16 |

> Note: D05 and D06 appear in both tracks — they serve as residency proof in Track A scenarios and as BPS packet documents in Track B scenarios. Each agent uses them independently.

---

## Shared Setup (Both Agents)

### Directory structure
```
spike/scripts/day3/
├── day3_track_a.py          # Track A runner (Agent A builds this)
├── day3_track_b.py          # Track B runner (Agent B builds this)
├── day3_track_a_results.jsonl
├── day3_track_b_results.jsonl
└── day3_summarize.py        # Summary script (either agent)
```

### Shared utilities
Both scripts should import from `day1_extract.py`:
- `to_jpeg_b64(path, pdf_dpi=100, jpeg_quality=90)` — image loading
- `score_field()` — field scoring

### Multi-image requests
Day 3 sends multiple document images in a single Ollama request. The Ollama chat API accepts multiple images in one message:

```python
r = client.chat(
    model="gemma4:e4b",
    messages=[{
        "role": "user",
        "content": prompt,
        "images": [notice_b64, doc1_b64, doc2_b64, ...]  # list of base64 strings
    }],
    options={"temperature": 0.0},
)
```

Label each document in the prompt text so the model can reference them by name (e.g. "Document 1: pay stub", "Document 2: lease agreement").

### JSON retry wrapper (required)
Wrap all parse calls with the Day 1 retry pattern:

```python
def parse_with_retry(raw: str) -> dict | None:
    # First attempt
    result = parse_response(raw)
    if result:
        return result
    # Try wrapping bare key:value output (E4B occasionally omits braces)
    try:
        return json.loads("{" + raw.strip() + "}")
    except Exception:
        return None
```

---

---

# TRACK A — SNAP Proof-Pack Builder

**Agent A owns everything in this section.**

---

## Track A Overview

Track A tests whether the model can act as a SNAP proof-pack assistant: given a DTA verification or recertification notice plus a set of resident documents, produce a structured proof-pack grid identifying which categories are covered, which are missing, and what action the resident should take — with a plain-language summary.

**Script to build:** `spike/scripts/day3/day3_track_a.py`  
**Output file:** `spike/scripts/day3/day3_track_a_results.jsonl`  
**Spike plan reference:** Section 3.4, "Track A — SNAP proof-pack builder prompt"

---

## Track A Prompt

Use this prompt verbatim from the spike plan (Section 3.4). Substitute `[DOCUMENT LIST]` with labeled document descriptions per scenario (see scenarios below).

```
You are helping a Massachusetts resident prepare documents for a
SNAP recertification or verification request.

The resident has shared:
1. A government notice (image attached)
2. The following documents they have at home (images attached):
[DOCUMENT LIST]

Your job:

Step 1: Read the notice and identify what proof categories are
being requested and the response deadline.

Step 2: For each document, classify it and assess whether it
likely satisfies one of the requested categories.

Step 3: Return a structured JSON result:

{
  "notice_summary": {
    "requested_categories": [],
    "deadline": "",
    "consequence": ""
  },
  "proof_pack": [
    {
      "category": "",
      "matched_document": "[document name or MISSING]",
      "assessment": "likely_satisfies|likely_does_not_satisfy|missing|uncertain",
      "confidence": "high|medium|low",
      "evidence": "[quote from document]",
      "caveats": ""
    }
  ],
  "action_summary": "[one paragraph in plain language for the resident]"
}

Important: never state or imply that a document is accepted by
the agency. Use 'appears to satisfy' and 'likely matches' only.
Always show caveats when confidence is not high.
```

---

## Track A Scenarios

Run all 8 scenarios. Each scenario specifies: which notice image, which document images, what the gold answers are, and what the scenario is testing.

### A1 — Strong match, single category
**Notice:** D01-degraded.jpg  
**Documents:** D03-degraded.jpg (pay stub), D06-degraded.jpg (utility bill), D09-degraded.jpg (state ID)  
**Document list for prompt:**
```
- Document 1: pay stub (D03)
- Document 2: utility bill (D06)  
- Document 3: state ID (D09)
```

**Gold answers:**
```json
{
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
}
```
**What this tests:** Basic end-to-end match. D03 (current pay stub) satisfies the income requirement. D06 and D09 are irrelevant to this notice — model should not force them into the proof pack. D06 is a utility bill which is irrelevant for an income-only notice.

**Key scoring checks:**
- Does `notice_summary.requested_categories` include `earned_income`?
- Does `notice_summary.deadline` extract `2026-04-15` (not the notice date)?
- Does `notice_summary.consequence` mention case closure?
- Is D03 matched to `earned_income` with `likely_satisfies`?
- Does the model correctly ignore D06 and D09 as not relevant to income category?

---

### A2 — Ambiguous residency proof included
**Notice:** D01-degraded.jpg  
**Documents:** D05-degraded.jpg (lease), D07-degraded.jpg (phone bill), D08-degraded.jpg (handwritten note)  
**Document list for prompt:**
```
- Document 1: lease agreement (D05)
- Document 2: cell phone bill (D07)
- Document 3: handwritten note (D08)
```

**Gold answers:**
```json
{
  "proof_pack": [
    {
      "category": "earned_income",
      "matched_document": "MISSING",
      "assessment": "missing"
    }
  ]
}
```
**What this tests:** None of the three documents satisfy earned_income. The model must correctly identify the proof pack as incomplete. D07 and D08 are residency documents, irrelevant to this income-only notice. D08 should be flagged as invalid proof regardless.

**Key scoring checks:**
- Is `earned_income` identified as the required category?
- Is `matched_document` = `MISSING` for earned_income?
- Does the model avoid incorrectly assigning D05/D07/D08 to income?
- Does `action_summary` tell the resident they need to submit income proof?

---

### A3 — Stale pay stub submitted
**Notice:** D01-degraded.jpg  
**Documents:** D04-degraded.jpg (stale pay stub — November 2025)  
**Document list for prompt:**
```
- Document 1: pay stub (D04)
```

**Gold answers:**
```json
{
  "proof_pack": [
    {
      "category": "earned_income",
      "matched_document": "D04",
      "assessment": "likely_does_not_satisfy",
      "caveats": "[date outside acceptable window]"
    }
  ]
}
```
**What this tests:** The model must detect that D04's pay date (November 28, 2025) is outside the 30-day window from the D01 notice date (April 1, 2026). This requires cross-document date reasoning — reading the notice date from D01 and the pay date from D04 and comparing them.

**Key scoring checks:**
- Is `assessment` = `likely_does_not_satisfy`?
- Does `caveats` mention the date mismatch or stale proof?
- Does `action_summary` tell the resident the pay stub is too old?

---

### A4 — Multi-category notice, full coverage
**Notice:** D02-degraded.jpg (recertification notice — income + residency + household expenses)  
**Documents:** D03-degraded.jpg (pay stub), D05-degraded.jpg (lease), D06-degraded.jpg (utility bill)  
**Document list for prompt:**
```
- Document 1: pay stub (D03)
- Document 2: lease agreement (D05)
- Document 3: utility bill (D06)
```

**Gold answers:**
```json
{
  "notice_summary": {
    "requested_categories": ["earned_income", "residency", "household_expenses"],
    "deadline": "2026-04-22",
    "consequence": "[case consequences]"
  },
  "proof_pack": [
    { "category": "earned_income", "matched_document": "D03", "assessment": "likely_satisfies" },
    { "category": "residency", "matched_document": "D05", "assessment": "likely_satisfies" },
    { "category": "household_expenses", "matched_document": "MISSING", "assessment": "missing" }
  ]
}
```
**What this tests:** Multi-category notice handling. D02 requests three categories; the resident has documents covering two. The conflicting signal in D02 (documentation deadline April 22 differs from interview date April 10) should be noted. Household expenses has no matching document.

**Key scoring checks:**
- Does `requested_categories` include all three categories?
- Is deadline correctly extracted as `2026-04-22` (not the interview date April 10)?
- Is `household_expenses` identified as missing?
- Does the model note the conflicting deadline/interview dates?

---

### A5 — Multi-category notice, partial coverage
**Notice:** D02-degraded.jpg  
**Documents:** D04-degraded.jpg (stale pay stub), D06-degraded.jpg (utility bill)  
**Document list for prompt:**
```
- Document 1: pay stub (D04 — stale)
- Document 2: utility bill (D06)
```

**Gold answers:**
```json
{
  "proof_pack": [
    { "category": "earned_income", "matched_document": "D04", "assessment": "likely_does_not_satisfy", "caveats": "[stale date]" },
    { "category": "residency", "matched_document": "D06", "assessment": "likely_satisfies" },
    { "category": "household_expenses", "matched_document": "MISSING", "assessment": "missing" }
  ]
}
```
**What this tests:** Stale proof + partial coverage in a multi-category context. Two of three categories are either missing or failing.

---

### A6 — Abstention scenario (blurry notice)
**Notice:** D01-blurry.jpg  
**Documents:** D03-degraded.jpg (pay stub)  
**Document list for prompt:**
```
- Document 1: pay stub (D03)
```

**Gold answers:**
```json
{
  "notice_summary": {
    "requested_categories": ["UNCERTAIN"],
    "deadline": "UNCERTAIN",
    "consequence": "UNCERTAIN"
  }
}
```
**What this tests:** The model must recognize that the notice is partially illegible and abstain on notice fields rather than hallucinating. The pay stub can still be classified but the notice fields should be UNCERTAIN. This directly tests the abstention behavior validated in W3.

**Key scoring checks:**
- Does the model flag notice fields as uncertain/unreadable rather than hallucinating dates?
- Does `action_summary` tell the resident the notice is unclear and they should contact DTA?

---

### A7 — Award letter submitted as income proof
**Notice:** D01-degraded.jpg  
**Documents:** D10-degraded.jpg (government award letter — housing assistance)  
**Document list for prompt:**
```
- Document 1: government award letter (D10)
```

**Gold answers:**
```json
{
  "proof_pack": [
    {
      "category": "earned_income",
      "matched_document": "D10",
      "assessment": "likely_does_not_satisfy",
      "caveats": "[housing assistance is not earned income]"
    }
  ]
}
```
**What this tests:** The critical semantic distinction — a government benefits letter is NOT earned income proof. This is the same test as W4 D10 but now in a full end-to-end context.

**Key scoring checks:**
- Is `assessment` = `likely_does_not_satisfy`?
- Does `caveats` or `evidence` explain that housing assistance ≠ earned income?
- Does `action_summary` tell the resident they need actual income documentation?

---

### A8 — Phone bill ambiguity
**Notice:** D01-degraded.jpg  
**Documents:** D07-degraded.jpg (cell phone bill)  
**Document list for prompt:**
```
- Document 1: cell phone bill (D07)
```

**Gold answers:**
```json
{
  "proof_pack": [
    {
      "category": "earned_income",
      "matched_document": "D07",
      "assessment": "likely_does_not_satisfy",
      "caveats": "[phone bill is not income proof]"
    }
  ]
}
```
**What this tests:** A phone bill cannot satisfy an earned income requirement under any policy interpretation. This is a simpler case than the residency ambiguity — there is no policy debate here. Model should reject cleanly.

---

## Track A Scoring

### What to score per scenario

For each scenario, score these dimensions:

**1. Notice reading accuracy** (A1–A5, A7, A8 only — not A6)
- `requested_categories` correct: +2 exact, +1 partial (right categories, wrong format), −1 wrong
- `deadline` correct: +2/+1/−1 (use normalized date comparison)
- `consequence` correct: +2/+1/0 (abstain acceptable if not visible)

**2. Proof-pack assessment accuracy**
For each category in the proof pack:
- `assessment` label correct: +2 exact, +1 right valence wrong label, −1 wrong valence
- `matched_document` correct: +2/+1/−1

**3. Missing-item detection** (scenarios A2, A4, A5)
Binary: did the model correctly identify that a required category has no matching document?
- Correct MISSING flag: pass
- Failed to flag MISSING: fail
- Target from spike plan: ≥80% recall

**4. Action/deadline extraction** (all scenarios with a readable notice)
- Did the deadline appear correctly in `action_summary` or `notice_summary`?
- Target from spike plan: ≥85%

**5. Abstention accuracy** (A6 only)
- Did the model return UNCERTAIN/unreadable for notice fields rather than hallucinating?
- Pass/fail

**6. Grounding quality** (spot check A1, A3, A7)
Manual check: does the `evidence` field quote something from the actual document, or is it generic?
- Target from spike plan: ≥75%

### Critical false positives to flag immediately
- A7: model accepts D10 award letter as earned income → STOP, log as critical failure
- A2: model assigns D08 handwritten note to any category as `likely_satisfies` → log as critical failure
- A3: model accepts D04 stale pay stub as `likely_satisfies` without date caveat → log

---

## Track A Output Format

Each JSONL record should include:
```json
{
  "scenario_id": "A1",
  "artifact_ids": ["D01", "D03", "D06", "D09"],
  "variant": "degraded",
  "model": "gemma4:e4b",
  "temperature": 0.0,
  "elapsed_s": 0.0,
  "parse_ok": true,
  "raw_response": "...",
  "parsed": { ... },
  "scores": {
    "notice_categories": { "score": 2, "label": "exact" },
    "deadline": { "score": 2, "label": "exact" },
    "consequence": { "score": 1, "label": "partial" },
    "proof_pack_assessments": [ ... ],
    "missing_item_detected": true,
    "abstention_correct": null
  },
  "critical_flags": []
}
```

---

## Track A Acceptance Criteria

| Metric | Target | Notes |
|--------|--------|-------|
| Notice category extraction accuracy | ≥85% | Across A1–A5, A7, A8 |
| Deadline extraction accuracy | ≥85% | Spike plan Section 3.6 |
| Proof-pack assessment accuracy | ≥70% | Across all proof_pack entries |
| Missing-item detection recall | ≥80% | A2, A4, A5 |
| Abstention on blurry notice (A6) | Pass | Must not hallucinate notice fields |
| Critical false positives (A7, A2) | 0 | Hard stop if violated |

---

---

# TRACK B — BPS Packet Checker

**Agent B owns everything in this section.**

---

## Track B Overview

Track B tests whether the model can act as a BPS school registration packet assistant: given a set of family documents, assess whether the packet satisfies all four BPS registration requirements, detect the duplicate-category rule violation if triggered, and produce a plain-language summary of what to bring and what to replace.

**Script to build:** `spike/scripts/day3/day3_track_b.py`  
**Output file:** `spike/scripts/day3/day3_track_b_results.jsonl`  
**Spike plan reference:** Section 3.4, "Track B — BPS packet checker prompt"

---

## Track B Prompt

Use this prompt verbatim from the spike plan (Section 3.4). Substitute `[DOCUMENT LIST]` with labeled document descriptions per scenario.

```
You are helping a family prepare their Boston Public Schools
registration packet.

The BPS registration checklist requires:
- Proof of child's age (birth certificate or passport)
- TWO proofs of Boston residency from DIFFERENT categories.
  Valid categories: lease/deed, utility bill, bank statement,
  government mail, employer letter, notarized affidavit.
  Two documents from the same category count as only ONE proof.
- Current immunization record
- Grade-level indicator (most recent report card or transcript,
  if applicable)

The family has uploaded the following documents (images attached):
[DOCUMENT LIST]

Return JSON:
{
  "requirements": [
    {
      "requirement": "",
      "status": "satisfied|questionable|missing",
      "matched_document": "[document name or MISSING]",
      "evidence": "[quote or observation]",
      "notes": ""
    }
  ],
  "duplicate_category_flag": true|false,
  "duplicate_category_explanation": "",
  "family_summary": "[plain language: what to bring, what to replace]"
}

Important: never state that the packet guarantees registration
or school assignment.
```

**Day 2 prompt fix — add this to the checklist section of the prompt:**
```
If both residency documents are leases or deeds, set
duplicate_category_flag to true and return
"same_residency_category_duplicate" in duplicate_category_explanation.
If a document is a phone bill or cell phone statement, its residency
status is policy-dependent — set status to "questionable" and note
this in the notes field.
```

---

## Track B Scenarios

Run all 8 scenarios. All scenarios use degraded JPG variants unless noted.

### B1 — Complete valid packet
**Documents:** D12-degraded.jpg (birth certificate), D05-degraded.jpg (lease), D06-degraded.jpg (utility bill), D13-degraded.jpg (immunization record)  
**Document list for prompt:**
```
- Document 1: birth certificate (D12)
- Document 2: lease agreement (D05)
- Document 3: utility bill (D06)
- Document 4: immunization record (D13)
```

**Gold answers:**
```json
{
  "requirements": [
    { "requirement": "proof_of_age", "status": "satisfied", "matched_document": "D12" },
    { "requirement": "residency_proof_1", "status": "satisfied", "matched_document": "D05" },
    { "requirement": "residency_proof_2", "status": "satisfied", "matched_document": "D06" },
    { "requirement": "immunization_record", "status": "satisfied", "matched_document": "D13" }
  ],
  "duplicate_category_flag": false
}
```
**What this tests:** Complete packet with two different residency categories (lease + utility bill). Should pass all four requirements. No duplicate flag.

**Key scoring checks:**
- All four requirements marked `satisfied`?
- `duplicate_category_flag` = false?
- D05 and D06 correctly identified as different residency categories?

---

### B2 — Missing immunization record
**Documents:** D12-degraded.jpg (birth certificate), D05-degraded.jpg (lease), D06-degraded.jpg (utility bill)  
**Document list for prompt:**
```
- Document 1: birth certificate (D12)
- Document 2: lease agreement (D05)
- Document 3: utility bill (D06)
```

**Gold answers:**
```json
{
  "requirements": [
    { "requirement": "proof_of_age", "status": "satisfied", "matched_document": "D12" },
    { "requirement": "residency_proof_1", "status": "satisfied", "matched_document": "D05" },
    { "requirement": "residency_proof_2", "status": "satisfied", "matched_document": "D06" },
    { "requirement": "immunization_record", "status": "missing", "matched_document": "MISSING" }
  ],
  "duplicate_category_flag": false
}
```
**What this tests:** Missing item detection. The immunization record is absent — model must flag it as missing, not hallucinate a match.

---

### B3 — Missing MMR vaccine (immunization record present but incomplete)
**Documents:** D12-degraded.jpg, D05-degraded.jpg, D06-degraded.jpg, D13-degraded.jpg (immunization record — note: D13 has all vaccines including MMR)  

> **Important for Agent B:** The spike plan references a D13b variant with MMR missing. If `D13b-degraded.jpg` exists in `spike/artifacts/degraded/`, use it. If not, use D13-degraded.jpg and note in the JSONL that the MMR-missing variant was not available — log as scenario skipped rather than fabricating a result.

**Gold answers (if D13b available):**
```json
{
  "requirements": [
    { "requirement": "immunization_record", "status": "questionable", "notes": "MMR vaccine not present in record" }
  ]
}
```

---

### B4 — Duplicate residency category (two leases)
**Documents:** D12-degraded.jpg (birth certificate), D05-degraded.jpg (lease 1), D14-degraded.jpg (lease 2 — same address), D13-degraded.jpg (immunization record)  
**Document list for prompt:**
```
- Document 1: birth certificate (D12)
- Document 2: lease agreement (D05)
- Document 3: second lease agreement (D14)
- Document 4: immunization record (D13)
```

**Gold answers:**
```json
{
  "requirements": [
    { "requirement": "proof_of_age", "status": "satisfied", "matched_document": "D12" },
    { "requirement": "residency_proof_1", "status": "satisfied", "matched_document": "D05" },
    { "requirement": "residency_proof_2", "status": "missing", "notes": "D14 is same category as D05 — does not count as second proof" },
    { "requirement": "immunization_record", "status": "satisfied", "matched_document": "D13" }
  ],
  "duplicate_category_flag": true,
  "duplicate_category_explanation": "same_residency_category_duplicate"
}
```
**What this tests:** The two-category rule. Two leases = one category. Model must set `duplicate_category_flag: true` and explain the violation. This is the D14 scenario that scored as partial in Day 2 — the prompt fix (explicit duplicate instruction) should resolve it here.

**Key scoring checks:**
- `duplicate_category_flag` = true?
- `duplicate_category_explanation` mentions same category?
- Residency proof 2 marked as `missing` or `questionable`, not `satisfied`?

---

### B5 — Spanish language document in packet
**Documents:** D12-degraded.jpg (birth certificate), D15-degraded.jpg (host family affidavit), D16-degraded.jpg (Spanish utility bill), D13-degraded.jpg (immunization record)  
**Document list for prompt:**
```
- Document 1: birth certificate (D12)
- Document 2: notarized affidavit (D15)
- Document 3: utility bill in Spanish (D16)
- Document 4: immunization record (D13)
```

**Gold answers:**
```json
{
  "requirements": [
    { "requirement": "proof_of_age", "status": "satisfied", "matched_document": "D12" },
    { "requirement": "residency_proof_1", "status": "satisfied", "matched_document": "D15" },
    { "requirement": "residency_proof_2", "status": "satisfied", "matched_document": "D16" },
    { "requirement": "immunization_record", "status": "satisfied", "matched_document": "D13" }
  ],
  "duplicate_category_flag": false
}
```
**What this tests:** Multilingual document in a packet. D16 is a Spanish utility bill — should be assessed as residency proof just like D06. D15 (affidavit) and D16 (utility bill) are different categories. No duplicate flag.

---

### B6 — Host family affidavit as residency proof
**Documents:** D12-degraded.jpg (birth certificate), D05-degraded.jpg (lease), D15-degraded.jpg (host family affidavit), D13-degraded.jpg (immunization record)  
**Document list for prompt:**
```
- Document 1: birth certificate (D12)
- Document 2: lease agreement (D05)
- Document 3: notarized host family affidavit (D15)
- Document 4: immunization record (D13)
```

**Gold answers:**
```json
{
  "requirements": [
    { "requirement": "proof_of_age", "status": "satisfied", "matched_document": "D12" },
    { "requirement": "residency_proof_1", "status": "satisfied", "matched_document": "D05" },
    { "requirement": "residency_proof_2", "status": "satisfied", "matched_document": "D15" },
    { "requirement": "immunization_record", "status": "satisfied", "matched_document": "D13" }
  ],
  "duplicate_category_flag": false
}
```
**What this tests:** Notarized affidavit as a valid second residency category. Lease (D05) and affidavit (D15) are different BPS categories. Both should be marked satisfied, no duplicate flag.

---

### B7 — Phone bill as residency proof (ambiguous)
**Documents:** D12-degraded.jpg (birth certificate), D05-degraded.jpg (lease), D07-degraded.jpg (cell phone bill), D13-degraded.jpg (immunization record)  
**Document list for prompt:**
```
- Document 1: birth certificate (D12)
- Document 2: lease agreement (D05)
- Document 3: cell phone bill (D07)
- Document 4: immunization record (D13)
```

**Gold answers:**
```json
{
  "requirements": [
    { "requirement": "residency_proof_2", "status": "questionable", "matched_document": "D07", "notes": "phone bill acceptance varies by BPS policy" }
  ]
}
```
**What this tests:** Phone bill ambiguity in the BPS context. The prompt fix from Day 2 (phone bills → `questionable`) should land here. Model should NOT mark D07 as `satisfied` with high confidence.

**Key scoring checks:**
- Is D07 marked `questionable` not `satisfied`?
- Does `notes` mention policy variability?

---

### B8 — Completely empty packet (all missing)
**Documents:** D09-degraded.jpg (state ID only — identity document, not age proof in BPS context)  
**Document list for prompt:**
```
- Document 1: state ID (D09)
```

**Gold answers:**
```json
{
  "requirements": [
    { "requirement": "proof_of_age", "status": "missing", "notes": "state ID is not accepted as BPS age proof — need birth certificate or passport" },
    { "requirement": "residency_proof_1", "status": "missing", "matched_document": "MISSING" },
    { "requirement": "residency_proof_2", "status": "missing", "matched_document": "MISSING" },
    { "requirement": "immunization_record", "status": "missing", "matched_document": "MISSING" }
  ],
  "duplicate_category_flag": false
}
```
**What this tests:** Missing-item detection across all four requirements. Also tests whether the model correctly notes that a state ID is not accepted as BPS proof of age (birth certificate or passport required).

**Key scoring checks:**
- All four requirements marked `missing`?
- Does the model note that state ID ≠ proof of age for BPS?
- Does `family_summary` clearly list all four missing items?

---

## Track B Scoring

### What to score per scenario

**1. Requirement status accuracy**
For each of the four BPS requirements in each scenario:
- `status` correct (`satisfied`/`questionable`/`missing`): +2 exact, +1 right category wrong label, −1 wrong
- `matched_document` correct: +2/+1/−1

**2. Missing-item detection** (B2, B3, B8)
Binary: did the model correctly flag missing requirements?
- Target from spike plan: ≥80% recall

**3. Duplicate category detection** (B4)
Binary: did the model set `duplicate_category_flag: true` and explain the violation?
- Pass/fail — this is the B4 hard test

**4. Abstention / questionable handling** (B3, B7)
Did the model use `questionable` rather than `satisfied` for ambiguous documents?
- Target from spike plan (abstention on ambiguous inputs): ≥80%

**5. Grounding quality** (spot check B1, B4, B5)
Manual check: does `evidence` quote something from the document?
- Target: ≥75%

### Critical cases to flag immediately
- B4: `duplicate_category_flag` = false when two leases submitted → log as critical failure
- B8: any requirement marked `satisfied` when document is D09 only → log as critical failure
- B7: D07 marked `satisfied` with high confidence for residency → log as warning

---

## Track B Output Format

Each JSONL record should include:
```json
{
  "scenario_id": "B1",
  "artifact_ids": ["D12", "D05", "D06", "D13"],
  "variant": "degraded",
  "model": "gemma4:e4b",
  "temperature": 0.0,
  "elapsed_s": 0.0,
  "parse_ok": true,
  "raw_response": "...",
  "parsed": { ... },
  "scores": {
    "requirements": [
      { "requirement": "proof_of_age", "status_score": 2, "document_score": 2 }
    ],
    "missing_item_detected": true,
    "duplicate_flag_correct": null,
    "abstention_correct": null
  },
  "critical_flags": []
}
```

---

## Track B Acceptance Criteria

| Metric | Target | Notes |
|--------|--------|-------|
| Requirement status accuracy | ≥70% | Across all requirements all scenarios |
| Missing-item detection recall | ≥80% | B2, B3, B8 |
| Duplicate category detection (B4) | Pass | Hard requirement |
| Abstention on ambiguous docs (B7) | Pass | Phone bill must be questionable |
| Critical false positives | 0 | B4 duplicate miss, B8 false satisfied |

---

## After Both Tracks Complete

Once both agents have results:

1. **Combine results** into a single Day 3 summary covering both tracks
2. **Fill in the Day 5 scoring table** (spike plan Section 3.6) with Track A and Track B actuals for:
   - Missing-item detection recall
   - Requirement mapping accuracy
   - Abstention on ambiguous inputs
   - Grounding quality
   - Action/deadline extraction (Track A only)
3. **Flag any critical false positives** from the critical case lists above — these go directly into the decision memo
4. **Proceed to Day 4** (demo build) — the Track A and Track B prompts defined here become the core of the Gradio interface
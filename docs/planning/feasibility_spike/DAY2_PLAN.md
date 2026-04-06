# Day 2 Execution Plan
## Document Classification and Category Mapping

**Spike reference:** Part 3, Section 3.3 (Day 2)  
**Model:** `gemma4:e4b`  
**Temperature:** `0.0`  
**Date:** April 2026

---

## Overview

Day 2 has two sequential steps:

1. **Step 1 — Classification** (~2 hours): Run all 16 degraded artifacts through the classification prompt. Score against ground truth document types. Target: ≥75% accuracy.
2. **Step 2 — Category mapping** (~3 hours): Run Track A and Track B relevant artifacts through the category mapping prompt. Score against the `category_assessment` fields in `ground_truth.csv`. Target: ≥70% accuracy.

Step 2 depends on Step 1 completing first — classification results feed into the mapping context. Run them sequentially.

All scripts should follow the same pattern as `spike/scripts/day1/day1_extract.py`: read ground truth from `ground_truth.csv`, write JSONL results, support `--append` for resume-friendly runs.

---

## Step 1: Document Classification

### Spike plan reference
Section 3.3, Step 1 — "Classification prompt (run against all 16 degraded artifacts)"

### What to build
Create `spike/scripts/day2/day2_classify.py`. It should:
- Load all 16 artifact IDs from `ground_truth.csv`
- Run the classification prompt against the **degraded JPG** variant of each (degraded is the meaningful test — clean PDFs were validated in W2)
- Also run against **D16-degraded** specifically to test Spanish language handling
- Write one JSONL record per artifact with: `artifact_id`, `variant`, `classification`, `confidence`, `evidence`, `elapsed_s`, `parse_ok`
- Score each result against the gold classification labels below
- Support `--artifacts`, `--runs`, `--model`, `--out`, `--append` flags (same interface as day1_extract.py)

### Classification prompt
Use this prompt verbatim (from spike plan Section 3.3, Step 1):

```
Look at this document image. Classify it into exactly one category:

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
```

### Gold classification labels
These are the expected `classification` values to score against:

| Artifact | Expected classification | Notes |
|----------|------------------------|-------|
| D01 | `government_notice` | DTA income verification notice |
| D02 | `government_notice` | DTA recertification notice |
| D03 | `pay_stub` | Current period pay stub |
| D04 | `pay_stub` | Stale pay stub — same type, different date |
| D05 | `lease_agreement` | Residential lease |
| D06 | `utility_bill` | Electric + gas bill |
| D07 | `phone_bill` | Cell phone bill |
| D08 | `handwritten_letter` | Informal landlord note — should NOT be lease_agreement |
| D09 | `identity_document` | State ID card |
| D10 | `government_award_letter` | Benefits award letter — NOT government_notice |
| D11 | `other` | BPS checklist has no exact taxonomy match |
| D12 | `birth_certificate` | Child birth certificate |
| D13 | `immunization_record` | Vaccine record |
| D14 | `lease_agreement` | Second lease — same type as D05 |
| D15 | `affidavit` | Notarized host family affidavit |
| D16 | `utility_bill` | Spanish utility bill — same type as D06 |

### Scoring for classification
Simple binary: exact match = pass (1), anything else = fail (0). Also record whether confidence was `high`, `medium`, or `low` — high confidence + wrong label is the dangerous case.

**Edge cases to watch:**
- D08: if model returns `lease_agreement` instead of `handwritten_letter`, that is a meaningful failure — the document is explicitly invalid proof and misclassifying it as a formal document is a safety issue
- D10: if model returns `government_notice` instead of `government_award_letter`, log it — this distinction matters for Track A category mapping
- D11: `other` is the gold answer but acceptable alternatives are `other` or any reasonable description. Do not penalize if the model says something reasonable but uses a non-taxonomy label — log it as a soft pass
- D16: Spanish document — confidence should not drop below `medium` just because the language is Spanish

### What to measure
- Classification accuracy % (target ≥75%)
- Accuracy broken down by: clean vs degraded, Track A vs Track B documents
- Confidence calibration: does `high` confidence correlate with correct classifications?
- Evidence grounding quality: does the evidence quote actual text from the document, or is it generic? (Manual spot-check — not automated)

---

## Step 2: Category Mapping

### Spike plan reference
Section 3.3, Step 2 — "Category mapping prompt (run after classification, for Track A relevant documents)" and the Track B checklist logic

### What to build
Create `spike/scripts/day2/day2_map.py`. It should:
- Only run against artifacts that have a `category_assessment` or `category_assessment_*` field in `ground_truth.csv`
- That is: **D04, D05, D06, D07, D08, D10, D14** (8 artifacts — see field names below)
- Run against both clean and degraded variants
- Write JSONL with: `artifact_id`, `variant`, `proof_category`, `assessment`, `confidence`, `evidence`, `caveats`, `elapsed_s`, `parse_ok`, `score`
- Score each result against the gold assessment values in `ground_truth.csv`

### Artifacts and their gold assessments
These come directly from `ground_truth.csv`:

| Artifact | Field name | Gold answer | Proof category to test against | Notes |
|----------|-----------|-------------|-------------------------------|-------|
| D04 | `category_assessment` | `likely_does_not_satisfy` | EARNED INCOME | Stale pay stub — date outside 30-day window |
| D05 | `category_assessment` | `likely_satisfies` | RESIDENCY | Current lease with matching address |
| D06 | `category_assessment` | `likely_satisfies` | RESIDENCY | Utility bill with matching address |
| D07 | `category_assessment` | `residency_ambiguous` | RESIDENCY | Phone bill — policy-dependent |
| D08 | `category_assessment` | `invalid_proof` | RESIDENCY | Handwritten note — should fail |
| D10 | `category_assessment_vs_earned_income` | `likely_does_not_satisfy` | EARNED INCOME | Award letter is NOT earned income |
| D14 | `category_assessment_bps_two_leases` | `same_residency_category_duplicate` | BPS RESIDENCY (two-category rule) | Two leases = one category = violation |

Note: D16 has `category_assessment: likely_satisfies` in ground truth — include it as an 8th mapping test (Spanish utility bill as residency proof).

### Category mapping prompt
Use this prompt verbatim (from spike plan Section 3.3, Step 2). Substitute `[document_type]` and `[proof_category]` and `[definition]` per artifact:

```
Document type: [classification from Step 1]

Requested proof category: [proof category name]

Category definition: [paste relevant definition — see definitions below]

Does this document appear to satisfy this proof category?

Return JSON:
{
  "assessment": "likely_satisfies|likely_does_not_satisfy|insufficient_information",
  "confidence": "high|medium|low",
  "evidence": "[exact quote from document supporting your answer]",
  "caveats": "[any concerns about date, legibility, policy edge cases]"
}

Return ONLY valid JSON. No markdown, no explanation.
```

### Category definitions to embed in prompts
Use these definitions for each proof category. These are the definitions the model should reason against:

**EARNED INCOME:**
> Acceptable earned income proof includes recent pay stubs from the last 30 days, employer letters on company letterhead, or recent self-employment records with income and expense documentation. Documents must reflect income received within the past 30 days from the date of the verification notice.

**RESIDENCY (DTA / SNAP):**
> Acceptable residency proof includes a current lease or rental agreement, utility bills (electric, gas, water) from the last 90 days showing the service address, bank statements showing the mailing address, or government mail addressed to the household. Cell phone bills are accepted by some DTA offices but policy varies by location.

**RESIDENCY (BPS two-category rule):**
> Boston Public Schools requires TWO proofs of Boston residency from DIFFERENT categories. Valid categories are: lease or deed, utility bill, bank statement, government mail, employer letter, notarized affidavit. Two documents from the same category count as only ONE proof. Important: a lease and a second lease from the same address are the same category.

### Scoring for category mapping
Use the same −1/0/+1/+2 scale as Day 1 where applicable, but for the assessment field use:
- **+2 (exact):** model returns exact gold label (`likely_satisfies`, `likely_does_not_satisfy`, `residency_ambiguous`, `invalid_proof`, `same_residency_category_duplicate`)
- **+1 (partial):** model returns the right valence but wrong label (e.g. `likely_does_not_satisfy` when gold is `invalid_proof` — correct rejection, wrong precision)
- **0 (insufficient_information):** model abstains — not a hallucination, but not useful
- **−1 (hallucinated):** model returns wrong valence (`likely_satisfies` when gold is `likely_does_not_satisfy` or vice versa)

**Critical cases to flag:**
- D10 returning `likely_satisfies` for earned income: this is the most dangerous error in the set — an award letter being accepted as income proof
- D07 returning `likely_satisfies` (high confidence) for residency: should be `residency_ambiguous` — overconfident acceptance of a policy-ambiguous document
- D08 returning anything other than `invalid_proof` or `likely_does_not_satisfy`: handwritten note must be rejected
- D14 NOT flagging the duplicate category violation: must detect `same_residency_category_duplicate`

### What to measure
- Mapping accuracy % (target ≥70%)
- False positive rate: how often does model accept a document that should be rejected?
- Abstention rate: how often does model return `insufficient_information`?
- Confidence calibration: does `high` confidence correlate with correct assessments?
- Evidence quality: does evidence field quote actual document text? (manual spot-check on D04, D07, D10)

---

## Output Files

```
spike/scripts/day2/
├── day2_classify.py                # Step 1 runner
├── day2_map.py                     # Step 2 runner  
├── day2_classification_results.jsonl
├── day2_mapping_results.jsonl
└── day2_summarize.py               # Summary script (optional — can reuse day1_summarize pattern)
```

---

## Acceptance Criteria

Day 2 passes and you can proceed to Day 3 if:
- Classification accuracy ≥75% on degraded artifacts
- Mapping accuracy ≥70% across all 8 mapping artifacts
- No false positives on the four critical cases (D08, D10 earned income, D07 high-confidence, D14 duplicate)
- Parse failures ≤2 runs (JSON retry wrapper should handle most formatting issues)

If classification accuracy is ≥75% but mapping accuracy is <70%:
- Per decision tree (Section 4.1): escalate to E4B (already done), add explicit proof-category definitions (already in prompts above), add 2–3 few-shot examples per category
- Do not proceed to Day 3 until mapping accuracy target is met or a documented exception is logged

If classification accuracy is <75%:
- Add a confirmation step per decision tree: after classifying, ask "what specific text or layout element led to this classification?" and review low-confidence cases manually
- Add failing cases as few-shot examples in the classification prompt

---

## Known Issues Carrying Forward from Day 1

These are documented failure modes from the Day 1 report that may affect Day 2 results. Do not re-investigate — log occurrences and move on:

- **Name confabulation on degraded inputs:** names in evidence quotes may be wrong. Score the `assessment` field, not the evidence names.
- **Date format preference:** model returns "Month Day, Year" format. Normalize dates before comparing in scorer.
- **E4B JSON wrapper omission:** retry wrapper from Day 1 is in place. If parse failures occur on new artifacts, apply same fix.
- **D11 degraded:** expected to fail classification and mapping on degraded input. Log but do not investigate further — architectural fix (binary confirmation prompt) is queued for Day 3.
- **D13 vaccine dates:** not a mapping artifact — not in scope for Day 2.

---

## Connection to Downstream Days

- Day 2 classification results feed directly into Day 3 Track A and Track B prompts — the `document_type` field in the Track A SNAP prompt and Track B BPS prompt comes from the Step 1 classification output
- Day 2 mapping accuracy is one of the 10 formal spike metrics in the Day 5 scoring table (Section 3.6 of spike plan — "Requirement mapping accuracy" target ≥70%)
- If Day 2 mapping passes, Day 3 can proceed as planned. If it fails, Day 3 prompt design needs to embed the category definitions more explicitly (the full definitions are already in the prompts above)
# Day 2 Feasibility Spike: Classification and Category Mapping

Day 2 tests whether `gemma4:e4b` can:
1. **Classify** degraded document images into taxonomy types
2. **Map** documents to proof categories with explicit policy definitions

This is a feasibility spike for the Civic tech document verification pipeline.

---

## Quick Start

```bash
# Setup (if not done)
cd /Users/danfinkel/github/civics
source .venv/bin/activate

# Run classification (Step 1)
cd spike/scripts/spike/day2
./day2_classify.sh

# Run mapping (Step 2)
./day2_map.sh

# View summary
./day2_summarize.sh
```

---

## What This Eval Tests

### Step 1: Document Classification

**Question**: Can the model correctly identify document types from degraded images?

**Test set**: 16 artifacts (D01-D16), degraded variant
**Categories**: pay_stub, lease_agreement, utility_bill, phone_bill, government_notice, government_award_letter, identity_document, birth_certificate, immunization_record, handwritten_letter, affidavit, other

**Gold labels** (from DAY2_PLAN.md):
| Artifact | Type | Notes |
|----------|------|-------|
| D01-D02 | government_notice | DTA notices |
| D03-D04 | pay_stub | Current and stale |
| D05, D14 | lease_agreement | Two leases for duplicate test |
| D06, D16 | utility_bill | D16 is Spanish |
| D07 | phone_bill | Policy-ambiguous |
| D08 | handwritten_letter | Must NOT be lease_agreement |
| D09 | identity_document | State ID |
| D10 | government_award_letter | Not government_notice |
| D11 | other | Checklist — no exact match |
| D12 | birth_certificate | |
| D13 | immunization_record | |
| D15 | affidavit | Host family |

**Target**: ≥75% accuracy

### Step 2: Category Mapping

**Question**: Given a document type and proof category definition, can the model assess whether the document satisfies the category?

**Test set**: 8 artifacts with category assessment fields
**Categories tested**:
- **EARNED INCOME**: Pay stubs, employer letters (30-day window)
- **RESIDENCY (DTA/SNAP)**: Lease, utility, bank statement, government mail (90-day window)
- **RESIDENCY (BPS two-category rule)**: Two proofs from different categories required

**Critical test cases**:
| Artifact | Category | Gold | Why Critical |
|----------|----------|------|--------------|
| D04 | EARNED INCOME | likely_does_not_satisfy | Stale pay date |
| D07 | RESIDENCY | residency_ambiguous | Phone bill policy variation |
| D08 | RESIDENCY | invalid_proof | Handwritten note insufficient |
| D10 | EARNED INCOME | likely_does_not_satisfy | Award letter ≠ earned income |
| D14 | BPS RESIDENCY | same_residency_category_duplicate | Two leases = one category |
| D16 | RESIDENCY | likely_satisfies | Spanish language handling |

**Target**: ≥70% accuracy, no false positives on critical cases

---

## Scripts

| Script | Purpose |
|--------|---------|
| `day2_classify.py` | Step 1: Run classification prompt against artifacts |
| `day2_map.py` | Step 2: Run category mapping prompt |
| `day2_summarize.py` | Generate report from JSONL results |
| `day2_classify.sh` | Convenience wrapper for classification |
| `day2_map.sh` | Convenience wrapper for mapping |
| `day2_summarize.sh` | Convenience wrapper for summary |

---

## Usage Examples

### Run full evaluation

```bash
cd spike/scripts/spike/day2

# Step 1: Classification
python3 day2_classify.py

# Step 2: Mapping
python3 day2_map.py

# Summary
python3 day2_summarize.py
```

### Run specific artifacts

```bash
# Test just D07 (phone bill edge case)
python3 day2_classify.py --artifacts D07
python3 day2_map.py --artifacts D07

# Test D04, D10 (earned income edge cases)
python3 day2_map.py --artifacts D04,D10
```

### Run with different model

```bash
# Test with E2B (faster, less capable)
python3 day2_classify.py --model gemma4:e2b --out day2_e2b_classification.jsonl
python3 day2_map.py --model gemma4:e2b --out day2_e2b_mapping.jsonl
```

### Multiple runs for stability testing

```bash
# Run 3 times per artifact to check consistency
python3 day2_classify.py --runs 3
python3 day2_map.py --runs 3
```

### Append mode (resume-friendly)

```bash
# Run some artifacts, then add more without overwriting
python3 day2_classify.py --artifacts D01-D08 --out results.jsonl
python3 day2_classify.py --artifacts D09-D16 --out results.jsonl --append
```

---

## Key Options

```bash
python3 day2_classify.py \
  --model gemma4:e4b \           # Model variant
  --artifacts D01,D03,D05 \      # Specific artifacts
  --variants degraded \          # clean, degraded, or both
  --runs 3 \                     # Multiple runs for stability
  --temp 0.0 \                   # Temperature (0 for reproducibility)
  --out my_results.jsonl         # Custom output path

python3 day2_map.py \
  --model gemma4:e4b \
  --artifacts D04,D05,D06,D07 \  # Mapping artifacts only
  --variants clean,degraded \    # Test both variants
  --runs 1 \
  --out my_mapping.jsonl
```

---

## Results Location

All results written to `spike/scripts/spike/day2/`:

| File | Description |
|------|-------------|
| `day2_classification_results.jsonl` | Step 1 classification results |
| `day2_mapping_results.jsonl` | Step 2 mapping results |
| `FINDINGS.md` | Detailed analysis and recommendations |

### Result Record Schema

**Classification** (`day2_classification_results.jsonl`):
```json
{
  "artifact_id": "D01",
  "variant": "degraded",
  "classification": "government_notice",
  "confidence": "high",
  "evidence": "...",
  "gold_classification": "government_notice",
  "score": 2,
  "score_label": "exact",
  "parse_ok": true,
  "elapsed_s": 38.93
}
```

**Mapping** (`day2_mapping_results.jsonl`):
```json
{
  "artifact_id": "D04",
  "variant": "clean",
  "document_type": "pay_stub",
  "proof_category": "EARNED INCOME",
  "assessment": "likely_does_not_satisfy",
  "confidence": "high",
  "evidence": "...",
  "caveats": "...",
  "gold_assessment": "likely_does_not_satisfy",
  "score": 2,
  "score_label": "exact",
  "critical_flags": [],
  "parse_ok": true,
  "elapsed_s": 48.66
}
```

---

## Interpreting Results

### Scoring

**Classification**:
- +2: Exact match to gold label
- +1: Soft pass (D11 "other" alternatives)
- 0: Wrong

**Mapping**:
- +2: Exact assessment label match
- +1: Partial (right valence, wrong label — e.g., `likely_does_not_satisfy` vs `invalid_proof`)
- 0: Abstain (`insufficient_information`)
- -1: Hallucinated (wrong valence — e.g., `likely_satisfies` when should reject)

### Critical Flags

Mapping results include `critical_flags` for dangerous errors:
- D10 returning `likely_satisfies` for earned income
- D07 returning `likely_satisfies` with `high` confidence
- D08 not rejected
- D14 not detecting duplicate category

---

## Ground Truth

Artifact definitions:
```
spike/artifacts/clean/html/ground_truth.csv
```

Synthetic documents:
```
spike/artifacts/clean/       # PDF versions
spike/artifacts/degraded/    # Photographed JPG versions
```

---

## Architecture Implications

Based on Day 2 findings:

1. **Classification is automation-ready**: 100% accuracy on degraded inputs means routing decisions can be automated.

2. **Mapping needs guardrails**: While overall accuracy is good (87.5%), edge cases (phone bills, duplicate categories) need:
   - Explicit prompt guidance for label precision
   - Human review for policy-ambiguous assessments
   - Post-processing rules for high-risk categories

3. **Evidence is not trustworthy**: Model "evidence" quotes are descriptive, not verbatim. Don't expose to users without OCR verification.

4. **Spanish handling is strong**: No degradation in classification or mapping for Spanish documents.

See `FINDINGS.md` for detailed analysis.

---

## Troubleshooting

**Timeout errors**: Increase `--http-timeout` (default 900s) or reduce `--pdf-dpi`

**Parse failures**: Check `raw_response` field — model may return markdown or malformed JSON

**Missing artifacts**: Ensure artifacts exist in `spike/artifacts/degraded/` or `spike/artifacts/clean/`

**Model not found**: Run `ollama pull gemma4:e4b`

---

## Next Steps

After Day 2:

1. **Review FINDINGS.md** for detailed analysis
2. **Apply prompt fixes** for D07 and D14 edge cases
3. **Proceed to Day 3** — Track A/B end-to-end evaluation

For questions, see the main spike plan at `docs/planning/feasibility_spike/DAY2_PLAN.md`.

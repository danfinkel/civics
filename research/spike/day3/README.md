# Day 3 — Track-Specific Matching Logic (End-to-End Scenarios)

Day 3 is the first full end-to-end pipeline test. The model receives a multi-document set and must:
1. Read a notice or checklist
2. Classify each uploaded document
3. Assess whether each satisfies the relevant proof category
4. Produce both a structured JSON result and a plain-language resident summary

All in a single inference call.

## Directory Structure

```
spike/scripts/day3/
├── day3_track_a.py              # Track A runner (SNAP Proof-Pack Builder)
├── day3_track_b.py              # Track B runner (BPS Packet Checker)
├── day3_track_a_results.jsonl   # Track A output
├── day3_track_b_results.jsonl   # Track B output
├── day3_summarize.py            # Summary script for both tracks
├── day3_track_b_summarize.py    # Track B standalone summary
├── day3_track_b.sh              # Track B convenience runner
└── README.md                    # This file
```

## Track A — SNAP Proof-Pack Builder

Tests whether the model can act as a SNAP proof-pack assistant: given a DTA verification or recertification notice plus a set of resident documents, produce a structured proof-pack grid identifying which categories are covered, which are missing, and what action the resident should take.

### Scenarios

| Scenario | Description | Notice | Documents |
|----------|-------------|--------|-----------|
| A1 | Strong match, single category | D01 | D03, D06, D09 |
| A2 | Ambiguous residency proof included | D01 | D05, D07, D08 |
| A3 | Stale pay stub submitted | D01 | D04 |
| A4 | Multi-category notice, full coverage | D02 | D03, D05, D06 |
| A5 | Multi-category notice, partial coverage | D02 | D04, D06 |
| A6 | Abstention scenario (blurry notice) | D01-blurry | D03 |
| A7 | Award letter submitted as income proof | D01 | D10 |
| A8 | Phone bill ambiguity | D01 | D07 |

### Usage

```bash
# Run all Track A scenarios
python day3_track_a.py

# Run specific scenarios
python day3_track_a.py --scenarios A1,A3,A7

# Use different model or temperature
python day3_track_a.py --model gemma4:e4b --temp 0.0

# Custom output path
python day3_track_a.py --out /path/to/results.jsonl
```

### Acceptance Criteria

| Metric | Target |
|--------|--------|
| Notice category extraction accuracy | ≥85% |
| Deadline extraction accuracy | ≥85% |
| Proof-pack assessment accuracy | ≥70% |
| Missing-item detection recall | ≥80% |
| Abstention on blurry notice (A6) | Pass |
| Critical false positives (A7, A2) | 0 |

## Track B — BPS Packet Checker

Tests whether the model can act as a BPS school registration packet assistant: given a set of family documents, assess whether the packet satisfies all four BPS registration requirements, detect the duplicate-category rule violation if triggered, and produce a plain-language summary.

**Note:** Track B is implemented in `day3_track_b.py` (separate file).

### Scenarios

| Scenario | Description | Documents |
|----------|-------------|-----------|
| B1 | Complete valid packet | D12, D05, D06, D13 |
| B2 | Missing immunization record | D12, D05, D06 |
| B3 | Missing MMR vaccine | D12, D05, D06, D13b (if available) |
| B4 | Duplicate residency category (two leases) | D12, D05, D14, D13 |
| B5 | Spanish language document in packet | D12, D15, D16, D13 |
| B6 | Host family affidavit as residency proof | D12, D05, D15, D13 |
| B7 | Phone bill as residency proof (ambiguous) | D12, D05, D07, D13 |
| B8 | Completely empty packet (all missing) | D09 |

### Usage

```bash
# Run all Track B scenarios
python3 day3_track_b.py

# Run specific scenarios
python3 day3_track_b.py --scenarios B1,B4,B7

# Use different model or temperature
python3 day3_track_b.py --model gemma4:e4b --temp 0.0

# Show summary of existing results
python3 day3_track_b_summarize.py day3_track_b_results.jsonl

# Or use the shell script
./day3_track_b.sh              # Run all scenarios
./day3_track_b.sh B1,B4        # Run specific scenarios
./day3_track_b.sh --summarize  # Show summary
```

### Acceptance Criteria

| Metric | Target |
|--------|--------|
| Requirement status accuracy | ≥70% |
| Missing-item detection recall | ≥80% |
| Duplicate category detection (B4) | Pass |
| Abstention on ambiguous docs (B7) | Pass |
| Critical false positives | 0 |

## Summary Script

After both tracks complete, generate a combined summary:

```bash
# Generate summary (requires both result files)
python day3_summarize.py

# Track A only
python day3_summarize.py --track-a-only

# Track B only
python day3_summarize.py --track-b-only

# Custom paths
python day3_summarize.py --track-a /path/to/a.jsonl --track-b /path/to/b.jsonl
```

## Output Format

### Track A JSONL Record

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
  "parsed": {
    "notice_summary": {
      "requested_categories": ["earned_income"],
      "deadline": "2026-04-15",
      "consequence": "case_closure"
    },
    "proof_pack": [...],
    "action_summary": "..."
  },
  "scores": {
    "notice_categories": {"score": 2, "label": "exact"},
    "deadline": {"score": 2, "label": "exact"},
    "proof_pack_assessments": [...],
    "missing_item_detected": true
  },
  "critical_flags": []
}
```

### Track B JSONL Record

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
  "parsed": {
    "requirements": [...],
    "duplicate_category_flag": false,
    "family_summary": "..."
  },
  "scores": {
    "requirements": [...],
    "missing_item_detected": true,
    "duplicate_flag_correct": null
  },
  "critical_flags": []
}
```

## Dependencies

- ollama
- pillow
- httpx

Shared utilities imported from `day1/day1_extract.py`:
- `to_jpeg_b64()` — image loading
- `score_field()` — field scoring

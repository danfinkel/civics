# Day 1 Feasibility Spike

Structured extraction at scale using Gemma 4 (E2B and E4B variants).

## Quick Start

```bash
# Setup (one time)
cd /Users/danfinkel/github/civics
python3 -m venv .venv
source .venv/bin/activate
pip install httpx ollama pillow pdf2image

# Pull models (one time)
ollama pull gemma4:e2b
ollama pull gemma4:e4b

# Run full Day 1 spike
cd spike/scripts/day1
python3 day1_extract.py

# Run with E4B
python3 day1_extract.py --model gemma4:e4b --out day1_e4b_results.jsonl
```

## Scripts

| Script | Purpose |
|--------|---------|
| `day1_extract.py` | Main extraction runner. Runs against all artifacts in ground_truth.csv |
| `day1_rescore.py` | Re-score existing JSONL without re-running model |
| `day1_summarize.py` | Generate human-readable report from results |
| `day1_rerun_fixed.py` | Re-run problematic artifacts with fixes |
| `day1_merge_and_rescore.py` | Merge original + re-run results |
| `day1_e4b_test.py` | Quick E4B test on worst 5 artifacts |

## Key Options

```bash
python3 day1_extract.py \
  --model gemma4:e4b \          # Model variant (e2b or e4b)
  --artifacts D01,D03 \          # Specific artifacts only
  --variants clean,degraded \    # Which variants to test
  --pdf-dpi 100 \                # Lower = faster, less tokens
  --http-timeout 900 \           # Seconds before giving up
  --out my_results.jsonl         # Output file
```

## Results Location

All results are written to this directory (`spike/scripts/day1/`):

| File | Description |
|------|-------------|
| `day1_extraction_results.jsonl` | Original E2B run (32 artifacts) |
| `day1_rerun_results.jsonl` | Re-run with prompt fixes (6 artifacts) |
| `day1_merged_results.jsonl` | Combined E2B original + fixes |
| `day1_e4b_full_results.jsonl` | Full E4B run (32 artifacts) — **primary baseline** |
| `day1_final_report.txt` | Human-readable summary |
| `day1_field_level_analysis.json` | **Design reference** — field confidence tiers, format issues, heuristics |

### For Design Phase

Use `day1_field_level_analysis.json` when building the UX:

```python
import json

with open('day1_field_level_analysis.json') as f:
    analysis = json.load(f)

# Fields to auto-accept
auto_accept = analysis['high_confidence_fields']['fields']

# Fields requiring user confirmation
user_review = analysis['low_confidence_fields']['fields']

# Document-type specific learnings
pay_stub_weaknesses = analysis['document_type_learnings']['pay_stubs']['weaknesses']
```

## Ground Truth

Artifact definitions and expected values:
```
spike/artifacts/clean/html/ground_truth.csv
```

Synthetic documents:
```
spike/artifacts/clean/       # PDF versions
spike/artifacts/degraded/    # Photographed JPG versions
```

## Benchmarks as Baselines

These results serve as reproducible benchmarks for future work:

| Model | Hallucination Rate | Exact+Partial | Mean Score (clean) | Mean Score (degraded) |
|-------|-------------------|---------------|-------------------|----------------------|
| E2B (original) | 42.0% | 20.2% | +0.243 | -0.162 |
| E2B (with fixes) | 42.0% | 20.2% | +0.269 | -0.146 |
| **E4B** | **39.9%** | **50.8%** | **+0.61** | **+0.52** |

Key findings preserved for future reference:
- **Timeouts**: E2B fails on high-res degraded images (D01, D05, D16). Fixed with lower DPI or E4B.
- **Hallucination patterns**: Dates and categories most prone to confabulation across both models.
- **Empty responses**: E2B returns all-empty for some degraded artifacts; E4B extracts values but may hallucinate.
- **JSON parsing**: E4B occasionally omits wrapping braces; fixed with JSON repair wrapper.

## Reproducing Results

To reproduce any benchmark:

```bash
# Exact reproduction of E2B baseline
python3 day1_extract.py \
  --model gemma4:e2b \
  --pdf-dpi 150 \
  --http-timeout 600 \
  --out reproduction_e2b.jsonl

# Exact reproduction of E4B results
python3 day1_extract.py \
  --model gemma4:e4b \
  --pdf-dpi 100 \
  --http-timeout 900 \
  --out reproduction_e4b.jsonl
```

## Troubleshooting

**Timeout errors**: Increase `--http-timeout` or reduce `--pdf-dpi`

**Parse failures**: Check `raw_response` field in JSONL — model may return non-JSON

**OOM errors**: E4B requires ~4GB RAM. Use E2B for memory-constrained environments.

## Next Steps for Hallucination Work

When you're ready to tackle the 40% hallucination rate:

1. **Confidence thresholds**: Add per-field confidence scores, flag low-confidence for review
2. **Multi-pass extraction**: Run twice, compare outputs, flag mismatches
3. **Domain-specific prompts**: Separate prompts per document type (pay stub, lease, etc.)
4. **Post-processing rules**: Validate dates are plausible, income within ranges, etc.

See `DAY1_FINDINGS.md` for detailed analysis.

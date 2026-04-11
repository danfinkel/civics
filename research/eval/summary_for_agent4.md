# Eval results summary for Kaggle writeup

**Status:** Awaiting JSONL runs. After experiments, regenerate from measured data:

```bash
cd research/eval
python3 generate_agent4_summary.py \
  results/d01_d03_baseline_*.jsonl \
  results/token_budget_ablation_*.jsonl \
  results/thermal_test_*.jsonl \
  -o summary_for_agent4.md \
  --device "iPhone 16"
```

Adjust glob paths to match your timestamped files. The generator **overwrites** `-o` with computed sections.

---

## Accuracy metrics

| Metric | Value |
|--------|-------|
| Parse OK rate | — |
| Field exact match rate | — |
| Field partial match rate | — |
| Hallucination rate | — |
| Avg score mean (0–2) | — |

## Latency metrics (on-device)

| Metric | Value |
|--------|-------|
| Mean (ms) | — |
| P95 (ms) | — |
| Std dev (ms) | — |

## Token budget tradeoff (D03 ablation)

| Token budget | Avg score | Latency mean (ms) |
|--------------|-----------|-------------------|
| 70 | — | — |
| 140 | — | — |
| 280 | — | — |
| 560 | — | — |
| 1120 | — | — |

**Finding:** —

## Key findings for writeup

1. —
2. —
3. —

## Raw data

- `research/eval/results/*.jsonl` (gitignored)

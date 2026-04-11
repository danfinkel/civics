# CivicLens evaluation harness

Drive repeated on-device inferences from a Mac over Wi‑Fi. The Flutter app must be built with `EVAL_MODE=true` (see `mobile/scripts/dev_deploy.sh --eval`), which starts an HTTP server on port **8080**.

In Xcode / device logs, look for: **`Eval server running on port 8080`**.

## Quick start

```bash
cd research/eval
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

export PHONE_IP=192.168.1.x   # Settings → Wi‑Fi → (i)

curl "http://${PHONE_IP}:8080/health"
# Expect: {"status":"ok","model":"gemma4-e2b",...}

python runner.py \
  --artifacts D01,D03 \
  --track a \
  --variants degraded \
  --runs 1 \
  --out results/smoke.jsonl
```

Or: `export PHONE_URL=http://192.168.1.x:8080`.

---

## Week 3 schedule (Agent 2 Wed–Fri)

Commands match `docs/sprint/week3/plans/agent2_wed_fri_plan.md`. Use the staged shell driver or run `runner.py` directly.

### Helper script

```bash
export PHONE_IP=192.168.1.x
./run_week3_experiments.sh baseline   # Wednesday
./run_week3_experiments.sh ablation   # Thursday
./run_week3_experiments.sh thermal    # Friday (metrics poll + long run)
# ./run_week3_experiments.sh all      # entire stack in one session
```

### Wednesday — D01/D03 baseline (20 runs × clean + degraded)

```bash
python runner.py \
  --artifacts D01,D03 \
  --track a \
  --variants clean,degraded \
  --runs 20 \
  --temp 0.0 \
  --cooldown 2.0 \
  --out "results/d01_d03_baseline_$(date +%Y%m%d_%H%M).jsonl"
```

**After the run:** paste `runner.py` stdout summary into the **Initial results** table below (or rely on `generate_agent4_summary.py`).

### Thursday — Token budget ablation (D03)

```bash
python runner.py \
  --artifacts D03 \
  --track a \
  --variants clean,degraded \
  --runs 10 \
  --temp 0.0 \
  --token-budgets 70,140,280,560,1120 \
  --ablation \
  --cooldown 3.0 \
  --out "results/token_budget_ablation_$(date +%Y%m%d_%H%M).jsonl"
```

### Friday — Thermal run (optional metrics poll)

```bash
python runner.py \
  --artifacts D01,D03,D04 \
  --track a \
  --variants degraded \
  --runs 30 \
  --temp 0.0 \
  --cooldown 1.0 \
  --metrics-log "results/thermal_metrics_$(date +%Y%m%d_%H%M).jsonl" \
  --metrics-interval 30 \
  --out "results/thermal_test_$(date +%Y%m%d_%H%M).jsonl"
```

**Plot latency vs run order** (upward drift can indicate thermal throttling):

```bash
python plot_run_latency.py results/thermal_test_<stamp>.jsonl -o results/thermal_latency.png
```

---

## Post-run: Agent 4 summary

From this directory, point at your timestamped JSONL files:

```bash
python generate_agent4_summary.py \
  results/d01_d03_baseline_*.jsonl \
  results/token_budget_ablation_*.jsonl \
  results/thermal_test_*.jsonl \
  -o summary_for_agent4.md \
  --device "iPhone 16"
```

Narrow the globs if multiple runs exist. Output is markdown ready for the Kaggle writeup handoff.

---

## Initial results — D01/D03 baseline

| Metric | Value |
|--------|-------|
| Date | — |
| Device | — |
| Parse OK rate | — |
| Avg score mean | — |
| Hallucination rate | — |
| Latency mean (ms) | — |
| Latency p95 (ms) | — |

---

## Token budget ablation — D03 pay stub

| Token budget | Avg score | Latency mean (ms) |
|--------------|-----------|-------------------|
| 70 | — | — |
| 140 | — | — |
| 280 | — | — |
| 560 | — | — |
| 1120 | — | — |

**Finding:** —

---

## Experiments run this week

| Experiment | Date | Results file | Key finding |
|------------|------|--------------|-------------|
| D01/D03 baseline | — | `results/d01_d03_baseline_*.jsonl` | — |
| Token budget ablation | — | `results/token_budget_ablation_*.jsonl` | — |
| Thermal test | — | `results/thermal_test_*.jsonl` | — |

---

## Endpoints (device)

| Path | Method | Purpose |
|------|--------|---------|
| `/health` | GET | Liveness + model label |
| `/infer` | POST | JSON: `image` (base64), `prompt`, optional `track`, `temperature`, `token_budget` |
| `/device` | GET | OS / processor info |
| `/metrics` | GET | RSS (when available), inference count, last latency |

### Runner flags (reference)

| Flag | Purpose |
|------|---------|
| `--metrics-log PATH` | Background poll of `/metrics` every `--metrics-interval` seconds (JSONL) |
| `--metrics-interval` | Seconds between polls (default 30) |

---

## Notes

- **Clean PDFs** under `spike/artifacts/clean/` are often not decodable as images for on-device OCR. Prefer **`degraded`** JPG for OCR-backed behavior; **clean** may be prompt-only if OCR returns empty.
- **`results/`** is gitignored; create it on first run.

---

## Troubleshooting

See `docs/sprint/week3/plans/agent2_wed_fri_plan.md` (Wi‑Fi, parse OK rate, latency, OOM).

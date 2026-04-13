# Agent 2 — Week 3 Plan: Wednesday-Friday

**Scope:** Execute Monte Carlo runs, token budget ablation, thermal characterization  
**Goal:** Real experimental data for Agent 4 Kaggle writeup by Friday EOD

---

## Wednesday: First Monte Carlo Run

### Prerequisites (15 min)
- iPhone on same Wi-Fi as Mac
- Model already downloaded on device (avoid download screen)
- Device charged >80%

### Setup
```bash
# Find iPhone IP: Settings > Wi-Fi > (i) next to network
export PHONE_IP=192.168.1.X

# Terminal 1: Start eval build on device
./mobile/scripts/dev_deploy.sh --eval

# Wait for "Eval server running on port 8080"

# Terminal 2: Verify connectivity
curl http://$PHONE_IP:8080/health
# Should return: {"status": "ok", "model": "gemma4-e2b", ...}
```

### Run D01/D03 Baseline (20 runs each, clean + degraded)

```bash
cd research/eval

python runner.py \
  --artifacts D01,D03 \
  --track a \
  --variants clean,degraded \
  --runs 20 \
  --temp 0.0 \
  --cooldown 2.0 \
  --out results/d01_d03_baseline_$(date +%Y%m%d_%H%M).jsonl
```

**Expected runtime:** ~15-20 minutes (20 runs × ~15s inference + 2s cooldown)

**Watch for:**
- Parse OK rate should be >90%
- Hallucination rate will vary by field type
- Latency mean should be ~11-15s

### Document initial findings

Add to `research/eval/README.md`:

```markdown
## Initial Results — D01/D03 Baseline

Date: [date]
Device: iPhone 16

| Metric | Value |
|--------|-------|
| Parse OK rate | X% |
| Avg score mean | X.XXX |
| Hallucination rate | X% |
| Latency mean | X,XXXms |
| Latency p95 | X,XXXms |
```

---

## Thursday: Token Budget Ablation

### Setup
Same as Wednesday — ensure device still on same Wi-Fi, eval build running.

### Run Visual Token Budget Ablation

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
  --out results/token_budget_ablation_$(date +%Y%m%d_%H%M).jsonl
```

**Expected runtime:** ~20 minutes (10 runs × 5 budgets × ~15s + cooldown)

**Expected finding:** Accuracy improves with higher token budgets on document-dense artifacts, with diminishing returns above 560. Latency increases roughly linearly.

### Document ablation findings

Add to README:

```markdown
## Token Budget Ablation — D03 Pay Stub

| Token Budget | Avg Score | Latency (ms) |
|--------------|-----------|--------------|
| 70 | X.XXX | X,XXX |
| 140 | X.XXX | X,XXX |
| 280 | X.XXX | X,XXX |
| 560 | X.XXX | X,XXX |
| 1120 | X.XXX | X,XXX |

**Finding:** [Your observation here — e.g., "Accuracy plateaus above 560 tokens"]
```

---

## Friday: Thermal Characterization + Handoff

### Morning (optional but valuable): Thermal Run

Extended experiment to detect thermal throttling:

```bash
python runner.py \
  --artifacts D01,D03,D04 \
  --track a \
  --variants degraded \
  --runs 30 \
  --temp 0.0 \
  --cooldown 1.0 \
  --out results/thermal_test_$(date +%Y%m%d_%H%M).jsonl
```

**Add metrics polling (optional enhancement):**

If you want to get fancy, poll `/metrics` during the run:

```bash
# In another terminal, while runner is going
curl http://$PHONE_IP:8080/metrics
```

Log memory and inference count. Plot latency vs run number — curve shape tells you if thermal throttling is happening.

### Afternoon: Final Documentation + Handoff to Agent 4

**Complete `research/eval/README.md` findings table:**

```markdown
## Experiments Run This Week

| Experiment | Date | Results File | Key Finding |
|------------|------|--------------|-------------|
| D01/D03 baseline | [date] | d01_d03_baseline_*.jsonl | Parse OK: X%, Hallucination: X% |
| Token budget ablation | [date] | token_budget_ablation_*.jsonl | Optimal: 560 tokens |
| Thermal test | [date] | thermal_test_*.jsonl | [if run] |
```

**Create summary for Agent 4:**

Do **not** hand-edit a markdown file. From `research/eval`, after JSONLs exist:

```bash
python3 generate_agent4_summary.py results/<your>.jsonl ... -o summary_for_agent4.md --device "…"
```

See **`research/eval/README.md`** (Playbook §5). The generator overwrites `-o` with computed metrics and per-file breakdowns.

<details>
<summary>Legacy hand-written outline (optional)</summary>

```markdown
# Eval Results Summary for Kaggle Writeup

## Accuracy Metrics
- Document classification: [from results if available, or reference spike 100%]
- Field extraction exact match: X%
- Field extraction partial match: X%
- Hallucination rate: X%
- Parse OK rate: X%

## Latency Metrics (iPhone 16, Gemma 4 E2B)
- Mean: X,XXXms
- P95: X,XXXms
- Std dev: XXXms

## Token Budget Tradeoff
- 70 tokens: X% accuracy, X,XXXms latency
- …

## Key Findings for Writeup
1. [Finding 1]
2. [Finding 2]
3. [Finding 3]

## Raw Data
All results in `research/eval/results/*.jsonl`
```

</details>

---

## Acceptance Criteria (Friday EOD)

- [ ] 20-run D01/D03 baseline completed with results saved to JSONL
- [ ] Token budget ablation completed (5 budgets × 10 runs)
- [ ] Summary statistics computed (accuracy, latency, hallucination rates)
- [ ] `research/eval/README.md` documents usage and findings
- [ ] Summary document created for Agent 4 with key numbers
- [ ] (Optional) Thermal characterization run completed

---

## Troubleshooting

**Mac cannot reach phone:**
- Verify same Wi-Fi network
- Check `PHONE_IP` is correct
- Try `ping $PHONE_IP`
- Check iOS local network permissions for the app

**Parse OK rate is low:**
- Check JSON retry logic is working
- Verify prompt format matches what model expects
- Check `raw_response` field in JSONL for clues

**Latency is very high (>30s):**
- Check if model is warming up (first run is slower)
- Verify Metal GPU is being used (check logs)
- May be thermal throttling — add longer cooldown

**Out of memory:**
- Reduce batch size (runs parameter)
- Add longer cooldown between runs
- Restart app between experiments

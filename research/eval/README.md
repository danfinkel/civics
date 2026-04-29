# CivicLens evaluation harness

Drive repeated **on-device** inferences from a Mac over Wi‑Fi. The iOS app must be built with **`EVAL_MODE=true`** (see `mobile/scripts/dev_deploy.sh --eval`), which starts an HTTP server on port **8080**.

In Xcode / device logs, look for: **`Eval server running on port 8080`**.

**Ground truth:** `spike/artifacts/clean/html/ground_truth.csv`  
**Scoring / rubric:** `runner.py` (`score_field`, `SCORING_RUBRIC_VERSION`)  
**Long-form findings + which JSONLs to cite:** `research/notes/ablation_insights.md`

---

## Real-World Image Quality Characterization

Script: `real_photo_characterizer.py`

**Experimental design:** Instead of fixing blur categories up front, we treat **LLM extraction correctness** (here: D01 `response_deadline` scored **exact** under the semantic rubric v3) as the **dependent** variable. We measure **image quality metrics** on real iPhone photos (Laplacian / Tenengrad sharpness, luminance, contrast, noise, rough skew, file size, etc.), run several **temperature-0** extractions per photo, label each photo **pass** if at least **2/3** runs get the deadline **exact**, then ask which metrics best separate pass from fail (Cohen’s d, Mann–Whitney, single-threshold accuracy, logistic regression with leave-one-out CV).

**Inversion rationale:** A single Laplacian-variance threshold can miss failures due to motion blur, poor light, or focus. By letting the data show which statistics track **observed** model failure, we can tune or replace the blur gate with predictors that match the **actual** extraction task.

**Outputs** (under `--out`, default `research/eval/results/real_photo_analysis/`; for [`blur_testing.ipynb`](blur_testing.ipynb) use `research/eval/results/blur_testing/` — see that folder’s README):

| File | Purpose |
|------|---------|
| `photo_attributes.csv` | Per-photo metrics (sharpness, luminance, **coverage, shadow, directional blur, document boundary** — see `ATTRIBUTE_COLS` in `real_photo_characterizer.py`) + `pass_rate` + `label` |
| `attribute_ranking.csv` | Effect size and non-parametric test per metric |
| `logistic_regression_report.txt` | LOO accuracy and standardized coefficients |
| `decision_rule.txt` | Best single-feature threshold vs Laplacian baseline |
| `summary.md` | Short narrative for writeups |
| `converted/` | JPEGs produced from HEIC (originals untouched) |

**Dependencies (in addition to `requirements.txt`):**  
`pip install pillow-heif opencv-python scipy scikit-learn pandas numpy ollama`  
(Use `opencv-python-headless` on servers without a display stack.)

**Quick run (metrics only — no model, no phone):**

```bash
cd research/eval
pip install pillow-heif opencv-python scipy scikit-learn pandas numpy
python3 real_photo_characterizer.py --photos /path/to/heic_or_jpeg --attributes-only
```

**Full run (local Ollama, `gemma4:e4b`):** start `ollama serve`, then same script without `--attributes-only` and `--backend ollama` (default). The script calls Ollama via **HTTP `/api/chat`** (not the Python `ollama` client) with an explicit read timeout, and prints a **heartbeat every 15s** while waiting — the first vision request can still take **many minutes** while the model loads. By default JPEGs are **resized to max 1024px** long edge (same as `web_demo`). Use `--ollama-max-long-edge 0` only if you accept very long runs; `--ollama-timeout` caps each request (default 600s).

**On-device eval server:** build the app with `EVAL_MODE=true`, set `--backend eval-server` and `--phone-ip` (or `PHONE_IP`); use `--photo-break` to cool the device between photos.

**How to read the output:** Large **Cohen’s d** with low **p-value** in `attribute_ranking.csv` means that metric shifts between pass and fail groups. The **decision rule** file compares a **data-driven** one-dimensional threshold to the best Laplacian threshold on the *same* photos — not a claim that one number generalizes to all users, but a diagnostic on your corpus. Add more **deliberately hard** photos to stabilize rankings.

---

## Prerequisites (checklist)

1. **Physical device** on the same Wi‑Fi as the Mac; app **Run** from Xcode (Product → Run) with eval build.
2. **From repo root or `research/eval`:** Python 3, venv optional but recommended.
3. **Install deps:** `pip install -r requirements.txt` (includes `requests`, `python-Levenshtein` for scoring / rescoring).
4. **Create output dir:** `mkdir -p research/eval/results` (the `results/` folder is gitignored).
5. **Point the runner at the phone:**
   - `export PHONE_IP=192.168.x.x` (Settings → Wi‑Fi → ⓘ), or  
   - `export PHONE_URL=http://192.168.x.x:8080`
6. **Sanity check:** `curl "http://${PHONE_IP}:8080/health"` → expect JSON with `"status":"ok"` and model id.

All commands below assume **`cd research/eval`** unless noted.

---

## Quick smoke test (1 inference)

```bash
cd research/eval
python3 runner.py \
  --artifacts D01,D03 \
  --track a \
  --variants degraded \
  --runs 1 \
  --out results/smoke.jsonl
```

The runner prints a **JSON summary** to stdout when the run finishes. Open `results/smoke.jsonl` to inspect one row (`field_scores`, `raw_response`, etc.).

---

## Playbook — repeat the main analyses

Use this section to reproduce experiments without hunting through the rest of the doc.

### At a glance

| Goal | Command / pattern |
|------|-------------------|
| **D01 prompt ablation (3 JSONLs)** | `./run_week3_experiments.sh prompt-ablation` |
| **Preview-only ablation (condition C)** | `python3 runner.py --semantic-preview …` |
| **Cross-artifact GT-shaped (e.g. D01,D02,D03)** | `python3 runner.py --artifacts D01,D02,D03` (no `--prompt-condition`) |
| **Re-score old JSONL (no phone)** | `python3 runner.py --rescore results/your_run.jsonl` |
| **Markdown summary for writeups** | `python3 generate_agent4_summary.py results/*.jsonl -o summary_for_agent4.md` |
| **Token budget sweep (D03)** | `./run_week3_experiments.sh token-ablation` |
| **Thermal + metrics poll** | `./run_week3_experiments.sh thermal` |
| **Debug clean PDF + generic** | `./run_week3_experiments.sh prompt-ablation-probe` |

---

### 1. D01 prompt ablation (primary: generic → semantic → semantic-preview)

**Recommended:** one shell driver — **three separate Python processes**, **three JSONLs** (thermal breathing room between conditions).

```bash
export PHONE_IP=192.168.x.x   # or PHONE_URL
cd research/eval
./run_week3_experiments.sh prompt-ablation
```

- **Outputs:** `results/ablation_generic_<STAMP>.jsonl`, `ablation_semantic_<STAMP>.jsonl`, `ablation_semantic_preview_<STAMP>.jsonl` (80 rows each: 4 variants × 20 runs).
- **Between sessions:** waits **`CONDITION_BREAK_S`** seconds (default **180**). Disable with `export CONDITION_BREAK_S=0`.

**Equivalent manual runs** (if you prefer not to use the script):

```bash
STAMP=$(date +%Y%m%d_%H%M)
for cond in generic semantic semantic-preview; do
  python3 runner.py \
    --artifacts D01 \
    --track a \
    --variants clean,clean_jpeg,degraded,blurry \
    --prompt-condition "$cond" \
    --runs 20 \
    --temp 0.0 \
    --cooldown 2.0 \
    --condition-break-s 0 \
    --out "results/ablation_${cond//-/_}_${STAMP}.jsonl"
  # optional: sleep 180 between conditions
done
```

**Single process, one JSONL** (all conditions in one file — filter rows by `prompt_condition` when analyzing):

```bash
python3 runner.py \
  --artifacts D01 \
  --track a \
  --variants clean,clean_jpeg,degraded,blurry \
  --prompt-condition generic,semantic,semantic-preview \
  --runs 20 \
  --temp 0.0 \
  --cooldown 2.0 \
  --condition-break-s 180 \
  --out "results/prompt_ablation_d01_$(date +%Y%m%d_%H%M).jsonl"
```

**Strict mode:** With `--prompt-condition`, the runner **aborts** on `/infer` errors or empty responses (so you do not log bad rows). For debugging device 500s, add **`--no-strict-infer`** and/or **`--print-raw-response`**.

---

### 2. semantic-preview only (notice preview + extract)

Shorthand for condition **C** on **D01** (`--artifacts` defaults to D01 if omitted):

```bash
python3 runner.py \
  --semantic-preview \
  --variants clean_jpeg,degraded,blurry \
  --runs 20 \
  --out "results/preview_smoke_$(date +%Y%m%d_%H%M).jsonl"
```

Prefer **`clean_jpeg`** over **`clean`** (PDF) if the device OCR path is flaky. **`semantic-preview`** cannot be combined with **`--prompt-condition`** or **`--ablation`**.

---

### 3. Cross-artifact run (GT-shaped prompts, not generic vs semantic ablation)

Omit **`--prompt-condition`**. JSON keys come from **`ground_truth.csv`** per artifact.

```bash
python3 runner.py \
  --artifacts D01,D02,D03 \
  --track a \
  --variants clean_jpeg,degraded \
  --runs 20 \
  --temp 0.0 \
  --cooldown 2.0 \
  --out "results/cross_gt_shaped_$(date +%Y%m%d_%H%M).jsonl"
```

Rows **do not** include `prompt_condition`, `critical_*`, or `abstention_rate` (those are prompt-ablation-only). **`--prompt-condition` with non-D01 artifacts is rejected** — see [Cross-artifact limitations](#cross-artifact-runs-limitations) below.

---

### 4. Re-score existing JSONL (no device, same rubric as `runner.py`)

Uses stored **`raw_response`** only; writes **`*_rescored_v3.jsonl`** when `--out` is left at default.

```bash
python3 runner.py --rescore results/ablation_semantic_20260412_1937.jsonl
# Optional explicit output:
python3 runner.py --rescore results/your.jsonl --out results/your_rescored.jsonl
```

Check **`scoring_rubric_version`** inside rows when citing strict **`hallucinated`** vs other labels. See [Scoring rubric](#scoring-rubric).

---

### 5. After any run: stdout + optional markdown summary

- **`runner.py`** always prints **`compute_summary()`** JSON at the end; prompt-ablation runs also print a **condition × variant** table.
- **Markdown for Kaggle / Agent 4:**

```bash
python3 generate_agent4_summary.py \
  results/ablation_semantic_20260412_2022.jsonl \
  results/cross_gt_shaped_20260412_2151.jsonl \
  -o summary_for_agent4.md \
  --device "iPhone (Gemma 4 E2B, on-device)"
```

**Quick per-artifact label counts** (example — adjust path):

```bash
python3 -c "
import json
from collections import defaultdict
counts = defaultdict(lambda: defaultdict(int))
runs = defaultdict(int)
with open('results/cross_gt_shaped_20260412_2151.jsonl') as f:
    for line in f:
        r = json.loads(line)
        aid = r['artifact_id']
        runs[aid] += 1
        for fs in r.get('field_scores', {}).values():
            counts[aid][fs['label']] += 1
for aid in sorted(counts):
    t = sum(counts[aid].values())
    h = counts[aid].get('hallucinated', 0)
    e = counts[aid].get('exact', 0)
    print(f'{aid}: {runs[aid]} runs, hallucinated={h}/{t} ({100*h/t:.1f}%), exact={e}/{t} ({100*e/t:.1f}%)')
"
```

---

### 6. Token budget ablation (D03, secondary)

```bash
./run_week3_experiments.sh token-ablation
# or see [Week 3 reference commands](#week-3-reference-commands-agent-2) below.
```

**Incompatible with `--prompt-condition`.**

---

### 7. Thermal run + latency plot

```bash
./run_week3_experiments.sh thermal
python3 plot_run_latency.py results/thermal_test_<STAMP>.jsonl -o results/thermal_latency.png
```

---

### 8. Legacy baseline (D01/D03, GT-shaped)

```bash
./run_week3_experiments.sh baseline
```

---

## Prompt ablation experiment (design)

**Hypothesis:** Semantically precise field naming reduces hallucination on degraded/blurry civic notices more than model-size scaling alone. Same **E2B** on-device model; differences are **prompt text** and, in condition C, **notice-first preview** (two-pass flow on device — see `InferenceService.inferRawWithNoticePreview`).

**Cite prompts:** `prompt_conditions.py` (`PROMPT_ABLATION_VERSION`).

| Condition | `prompt_condition` | What varies |
|-----------|-------------------|-------------|
| **A — Generic** | `generic` | Six generic keys; critical deadline scored as **`key_date`** → GT **`response_deadline`**. |
| **B — Semantic** | `semantic` | Seven D01 semantic keys + date disambiguation. |
| **C — Semantic + preview** | `semantic-preview` | Same prompt as B; POST includes **`notice_preview_first: true`**. |

**Variants:** `clean` (PDF), `clean_jpeg` (`*-clean-raster.jpg`), `degraded`, `blurry` under `spike/artifacts/...`. Regenerate JPEGs after PDF changes: `python3 ../../spike/scripts/rasterize_clean_pdfs_to_jpeg.py` (from repo root; needs `pymupdf`, `pillow`).

**JSONL fields (prompt rows):** `prompt_condition`, `prompt_ablation_version`, `notice_preview_first`, `critical_*`, `abstention_rate`, `preview_elapsed_ms` / `extract_elapsed_ms` (C only), plus `field_scores`, `elapsed_ms`, `scoring_rubric_version`, etc.

**Metrics:** deadline via `critical_label`; strict hallucination = share of `field_scores` with label **`hallucinated`**; `abstention_rate`; `elapsed_ms`.

**Run:** use [§1 Playbook](#1-d01-prompt-ablation-primary-generic--semantic--semantic-preview).

### Cross-artifact runs (limitations)

1. **Multi-artifact + GT-shaped prompts:** omit `--prompt-condition`; use [§3 Playbook](#3-cross-artifact-run-gt-shaped-prompts-not-generic-vs-semantic-ablation).
2. **Generic vs semantic ablation on non-D01:** **not implemented** — `prompt_conditions.py` only defines D01 field maps and deadline key.

---

## Week 3 reference commands (Agent 2)

Staged driver (requires `PHONE_IP` or `PHONE_URL`):

```bash
export PHONE_IP=192.168.x.x
cd research/eval
./run_week3_experiments.sh prompt-ablation        # PRIMARY: 3 JSONLs
./run_week3_experiments.sh prompt-ablation-probe    # 5× generic/clean + raw dump
./run_week3_experiments.sh baseline                 # D01/D03 GT-shaped
./run_week3_experiments.sh token-ablation           # D03 token sweep
./run_week3_experiments.sh thermal                # long run + /metrics
# ./run_week3_experiments.sh all                    # prompt → token → thermal
```

**Wednesday-style baseline (explicit):**

```bash
python3 runner.py \
  --artifacts D01,D03 \
  --track a \
  --variants clean,degraded \
  --runs 20 \
  --temp 0.0 \
  --cooldown 2.0 \
  --out "results/d01_d03_baseline_$(date +%Y%m%d_%H%M).jsonl"
```

**Token budget ablation (explicit):**

```bash
python3 runner.py \
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

**Thermal (explicit):**

```bash
python3 runner.py \
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

Plan context: `docs/sprint/week3/plans/agent2_wed_fri_plan.md`.

---

## Optional: log tables for a given sprint

| Metric | Value |
|--------|-------|
| Date | — |
| Device | — |
| Parse OK rate | — |
| Avg score mean | — |
| Hallucination rate | — |
| Latency mean (ms) | — |
| Latency p95 (ms) | — |

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
| `/infer` | POST | JSON: `image` (base64), `prompt`, optional `track`, `temperature`, `token_budget`, **`notice_preview_first`** (bool) |
| `/device` | GET | OS / processor info |
| `/metrics` | GET | RSS (when available), inference count, last latency |

---

## `runner.py` flags (reference)

| Flag | Purpose |
|------|---------|
| `--artifacts` | Comma-separated ids (`D01,D03`). Required for inference; ignored with `--rescore`. |
| `--variants` | `clean`, `clean_jpeg`, `degraded`, `blurry`, or custom degraded basename (default `clean,degraded`). |
| `--runs` | Monte Carlo repeats per (artifact × variant × cell) (default 20). |
| `--out` | JSONL path (default `research/eval/results/run.jsonl`). |
| `--track` | App track label (default `a`). |
| `--temp` | Sampling temperature (default 0.0). |
| `--cooldown` | Seconds between consecutive `/infer` calls in one experiment (default 2). |
| `--phone-url` | Override base URL (else `PHONE_URL` or `http://PHONE_IP:8080`). |
| `--prompt-condition` | Comma-separated: `generic`, `semantic`, `semantic-preview` (**D01 only**). Incompatible with `--ablation`. |
| `--semantic-preview` | Shorthand: only `semantic-preview`, default `--artifacts D01` if omitted. |
| `--condition-break-s` | Cooldown **between** prompt conditions in one process (default 180; use 0 to disable). |
| `--no-strict-infer` | Record rows even when `/infer` errors or body empty (prompt-ablation default is strict). |
| `--print-raw-response` | Echo each model response to stdout (debug). |
| `--skip-prebatch-health` | Skip latency-gated `/health` before each prompt batch (not recommended). |
| `--health-max-mean-ms` / `--health-retry-wait-s` / `--health-max-rounds` | Pre-batch health gate tuning. |
| `--infer-timeout` | Per-request timeout seconds (default 120; preview path uses a multiple on the client). |
| `--token-budget` | Single optional max output tokens. |
| `--token-budgets` + `--ablation` | Matrix over budgets (no `--prompt-condition`). |
| `--metrics-log` / `--metrics-interval` | Background `/metrics` sampling. |
| `--rescore PATH` | Re-score JSONL from `raw_response`; default output `*_rescored_v3.jsonl` unless `--out` set. |

---

## Scoring rubric

Field-level scoring lives in `runner.py` (`score_field`, `SCORING_RUBRIC_VERSION`). Each `field_scores` entry includes `score`, `label`, and `correct_field` (False only for **misattribution**).

| Label | Score | Meaning |
|-------|------:|---------|
| **exact** | +2 | Standard-normalized extracted equals expected (includes matching calendar dates after canonical parse). |
| **partial** | +1 | Substring match after standard normalization (commas/spaces/`$` stripped, lowercased). |
| **format_mismatch** | +1 | Same underlying value, different surface form after **aggressive** normalization (lowercase; all non-alphanumeric removed). Example: `EARNED INCOME` vs `earned_income` → `earnedincome`. |
| **transcription_error** | 0 | OCR/blur: Levenshtein on standard-normalized strings ÷ `len(expected_norm)` ≤ **`LEVENSHTEIN_THRESHOLD` (0.45)**, and not already partial. |
| **unreadable** | 0 | Model emitted `UNREADABLE` (intended abstention). |
| **missing** | 0 | Empty / null extraction. |
| **semantic_paraphrase** | 0 | Short snake_case categorical GT (≤20 chars, contains `_`), extracted is natural language (>30 chars), and ≥50% of expected’s non-stopword underscore tokens appear in extracted. |
| **verbatim_quote** | 0 | Long extracted text in the **correct** field vs short categorical GT; checked before misattribution. |
| **misattribution** | −1 | Extracted aligns with **another** field’s GT. `correct_field`: **false**. |
| **hallucinated** | −1 | No relationship to expected after the checks above (strict fabrication). |

**Aggregates:** `compute_summary()` sets **`hallucination_rate`** = fraction of judgments with label **`hallucinated` only**. Per-label counts: `field_label_counts`, `field_label_rate_*`.

**Re-score:**

```bash
python3 runner.py --rescore results/ablation_semantic_20260412_1546.jsonl
# → results/ablation_semantic_20260412_1546_rescored_v3.jsonl (unless --out is set)
```

---

## Notes

- **Clean PDF** (`clean`) is often a poor OCR baseline; prefer **`clean_jpeg`** or **`degraded`** for behavior that matches phone photos.
- **`results/`** is gitignored; create it before first run (`mkdir -p results`).

---

## Troubleshooting

| Symptom | Things to try |
|---------|----------------|
| Cannot connect | Same Wi‑Fi; confirm `Eval server running on port 8080`; firewall; correct `PHONE_IP`. |
| **`semantic-preview` /infer 500** | Device build must handle `notice_preview_first`; try **`clean_jpeg`**; use **`--no-strict-infer`** to capture error text in JSONL; **`--print-raw-response`**. |
| Prompt ablation aborts mid-run | **`--no-strict-infer`** for debugging; fix device OOM/thermal; increase **`--infer-timeout`**. |
| High `/health` latency | Runner retries then exits; cool device; use **`--skip-prebatch-health`** only if you accept lower gate quality. |

More context: `docs/sprint/week3/plans/agent2_wed_fri_plan.md` (Wi‑Fi, parse OK, latency, OOM).

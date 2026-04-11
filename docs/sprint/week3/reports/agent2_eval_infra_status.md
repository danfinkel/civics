# CivicLens — Week 3 Status (Agent 2: Eval infrastructure)

**Report for:** Project management  
**Sprint:** Week 3 (April 14–18, 2026)  
**Scope:** Agent 2 track — on-device eval server + Mac-side Monte Carlo harness  
**Overall status:** **Green** — **Monday–Wednesday plan items for this track are implemented in-repo.** Thursday/Friday items are **execution** (runs on hardware + optional thermal tooling), not missing code.

---

## Executive summary

We landed the **eval automation spine** the plan calls for:

1. **On the phone (debug / eval builds only):** When the app is built with `EVAL_MODE=true` (e.g. `./mobile/scripts/dev_deploy.sh --eval`), an embedded **HTTP server** starts on **port 8080** with **`/health`**, **`/infer`**, **`/device`**, and **`/metrics`**. Normal resident builds are unchanged.

2. **On the Mac:** **`research/eval/runner.py`** loads spike **ground truth**, pulls **artifact images** (clean / degraded / blurry paths), posts to the phone’s **`/infer`**, scores JSON fields, writes **JSONL**, and prints **summary stats**. **Token-budget ablation** is supported via **`--ablation`** + **`--token-budgets`**.

3. **Inference path:** **`InferenceService.inferRaw()`** runs **OCR + Gemma turn-wrapped prompt** into the existing **llama.cpp** client (adapted from the plan’s multimodal snippet because the current stack is text-in after OCR, not `visualTokenBudget` in-process).

**PM takeaway:** Engineering can drive **repeatable, unattended inference batches** from a laptop once the phone’s IP is known and the eval build is running. What remains for the **full week-3 story** is **running** the planned Monte Carlo and ablation jobs, **filling** the README results table with real numbers, and optionally adding **metrics polling / plots** for thermal characterization (Friday morning in the plan).

---

## Deliverables (vs Agent 2 plan)

| Area | Deliverable | Status | Notes |
|------|-------------|--------|--------|
| **Mobile deps** | `shelf`, `shelf_router` in `pubspec.yaml` | Done | `flutter pub get` |
| **Eval server** | `mobile/lib/eval/eval_server.dart` | Done | Listens on `0.0.0.0:8080`; JSON POST `/infer` |
| **Boot wiring** | `main.dart` + `kEvalMode` | Done | Uses `mobile/lib/core/utils/eval_mode.dart` (no duplicate flag) |
| **Inference** | `inferRaw()` on `InferenceService` | Done | OCR append + `maxTokens` ← `token_budget`; temperature passed through (isolate sampler still greedy) |
| **Python** | `research/eval/runner.py` | Done | GT, prompts, scoring, cooldown loop, CLI, ablation mode |
| **Docs / deps** | `requirements.txt`, `README.md` | Done | Quick start, `PHONE_IP` / `PHONE_URL`, PDF vs JPG caveat |
| **Hygiene** | `research/eval/results/` gitignored | Done | Root `.gitignore` |
| **Friday (plan)** | `poll_metrics_during_experiment` + latency plots | **Not built** | Small follow-up in `runner.py` + optional matplotlib script |
| **Thu–Fri (plan)** | Live 20-run + ablation + thermal run | **Not executed** | Requires device + Wi‑Fi; outputs feed README + Agent 4 |

---

## Acceptance criteria (plan checklist)

| Criterion | Code / process |
|-----------|----------------|
| Eval server starts with `EVAL_MODE=true` | Implemented — verify on device after `./mobile/scripts/dev_deploy.sh --eval` |
| `/health` reachable from Mac | Implemented — `curl http://<PHONE_IP>:8080/health` |
| `/infer` returns response + timing | Implemented |
| `/metrics` returns memory + inference count | Implemented (`memory_used_mb` may be null if `ProcessInfo` unavailable) |
| Mac runner gets valid response | Implemented — `runner.py` probes `/health` before runs |
| 20-run D01/D03 unattended | **Run** when PM/engineering schedules device time |
| Token budget ablation produces results | **Run** with `--ablation --token-budgets ...` |
| JSONL includes field_scores, avg_score, hallucination_count | Implemented |
| README documents usage + findings | Usage done; **findings table** still to fill after runs |

---

## Dependencies and handoffs

- **Agent 1:** **`--eval`** and **`kEvalMode`** are prerequisites; already shipped per Agent 1 week-3 status.
- **Agent 4 (Kaggle / writeup):** After Thursday/Friday runs, share **summary JSON** (accuracy, latency, ablation) from `runner.py` stdout + JSONL paths listed in `research/eval/README.md`.
- **All agents:** Eval base URL pattern **`http://<device-ip>:8080`** for any cross-team testing.

---

## Risks and mitigations

| Risk | Mitigation |
|------|------------|
| **Mac cannot reach phone** | Same Wi‑Fi, correct `PHONE_IP`; iOS local-network / firewall quirks — document first successful `curl /health` in run notes. |
| **Clean PDFs + OCR** | README notes: **raster JPG** (e.g. degraded artifacts) is reliable; PDF bytes often skip OCR — use **`--variants degraded`** for grounded text-in. |
| **Long inference times** | Runner supports **`--infer-timeout`**; cooldown between runs reduces thermal stacking. |
| **Temperature / token budget vs actual GPU path** | `token_budget` maps to **max output tokens**; **temperature** is not yet applied inside the llama isolate (greedy sampler) — document if comparing to cloud temperature sweeps. |

---

## Appendix — Key paths

| Area | Path |
|------|------|
| Eval server | `mobile/lib/eval/eval_server.dart` |
| Eval boot + flag | `mobile/lib/main.dart`, `mobile/lib/core/utils/eval_mode.dart` |
| `inferRaw` | `mobile/lib/core/inference/inference_service.dart` |
| Mac runner | `research/eval/runner.py` |
| Harness docs | `research/eval/README.md`, `research/eval/requirements.txt` |
| Deploy with eval | `mobile/scripts/dev_deploy.sh --eval` |

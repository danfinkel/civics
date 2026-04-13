# CivicLens — Week 3 Status (Agent 2: Wed–Fri plan delivery)

**Report for:** Project management  
**Sprint:** Week 3 (April 14–18, 2026)  
**Scope:** Follow-up to `docs/sprint/week3/plans/agent2_wed_fri_plan.md` — tooling, docs, and handoff assets for Monte Carlo, ablation, and thermal characterization  
**Overall status:** **Green (engineering deliverables)** — **in-repo automation is complete.** **Yellow (data)** — **JSONL runs and filled metrics still require on-device execution** on your schedule.

---

## Executive summary

After the **eval server + `runner.py` baseline** (prior report), we implemented everything in **Agent 2 Wed–Fri** that **does not depend on a physical iPhone**:

- **Background `/metrics` sampling** during long runs (thermal / memory trail).
- **Latency vs run-index plotting** for spotting drift or throttling.
- **One-command markdown summary** for **Agent 4 / Kaggle** from measured JSONL.
- **Staged shell driver** for Wednesday baseline, Thursday ablation, and Friday thermal (run separately or `all`).
- **README** expanded with the exact commands, placeholder **results tables**, and troubleshooting pointers.
- **Small eval-server polish** so logs and `/health` match the written runbook (`gemma4-e2b`, “Eval server running on port 8080”).

**PM takeaway:** The team is not blocked on **scripts or documentation**. The **remaining work is calendar + hardware**: run the three experiments when the device is on Wi‑Fi, then run **`generate_agent4_summary.py`** (or paste summaries into README). No further app or harness **features** are required for the plan as written.

---

## What shipped (this increment)

| Item | Location | Purpose |
|------|----------|---------|
| Metrics polling | `research/eval/runner.py` — `--metrics-log`, `--metrics-interval` | Append JSONL samples from **`GET /metrics`** for the whole experiment (Friday option in plan). |
| Partial-match rate | `research/eval/runner.py` — `compute_summary()` | **`partial_rate`** for clearer accuracy language in writeups. |
| Latency plot | `research/eval/plot_run_latency.py` | PNG: **elapsed_ms vs JSONL row order** (thermal narrative). |
| Agent 4 summary | `research/eval/generate_agent4_summary.py` | Builds **`summary_for_agent4.md`** (or any `-o` path) from one or more JSONL files. Regenerate after each eval batch (see `research/eval/README.md` playbook); the repo does not ship a placeholder copy. |
| Runbook script | `research/eval/run_week3_experiments.sh` | `baseline` \| `ablation` \| `thermal` \| `all` — mirrors Wed/Thu/Fri commands. |
| Harness docs | `research/eval/README.md` | Full Wed–Fri flow, post-run steps, tables to fill, endpoint reference. |
| Plotting dependency | `research/eval/requirements.txt` | **`matplotlib`** added. |
| Health / logs | `mobile/lib/eval/eval_server.dart` | **`model`: `gemma4-e2b`**; explicit **“Eval server running on port 8080”** log line. |

---

## Relationship to prior status report

[agent2_eval_infra_status.md](agent2_eval_infra_status.md) listed **metrics polling + plots** as not built and Thu–Fri as not executed. **This report supersedes those rows for code:** polling and plotting are **in**. **Execution** (20-run baseline, ablation, thermal) is still **on the team**, not in CI.

---

## What you still do on the calendar (unchanged from plan)

| When | Action |
|------|--------|
| **Wednesday** | `run_week3_experiments.sh baseline` or equivalent `runner.py` command; save JSONL. |
| **Thursday** | `ablation` step; save JSONL. |
| **Friday (optional)** | `thermal` step with **`--metrics-log`**; optional **`plot_run_latency.py`**. |
| **After runs** | `python generate_agent4_summary.py … -o summary_for_agent4.md`; update **README** experiment table if you want a single canonical doc. |

**Prerequisites (unchanged):** same Wi‑Fi as Mac, **`PHONE_IP`** or **`PHONE_URL`**, model already on device, eval build (`dev_deploy.sh --eval`), device charged.

---

## Risks (brief)

| Risk | Note |
|------|------|
| **Clean PDF + OCR** | Degraded **JPG** remains the reliable path for text-from-image; README calls this out. |
| **Long sessions** | Use **`--infer-timeout`** and cooldowns if the phone thermals or the network flakes. |
| **Multiple JSONL globs** | When generating Agent 4 summary, narrow `results/*.jsonl` globs if several dated runs exist. |

---

## Appendix — key paths

| Artifact | Path |
|----------|------|
| Wed–Fri plan | `docs/sprint/week3/plans/agent2_wed_fri_plan.md` |
| Harness README | `research/eval/README.md` |
| Runner | `research/eval/runner.py` |
| Staged experiments | `research/eval/run_week3_experiments.sh` |
| Plot script | `research/eval/plot_run_latency.py` |
| Agent 4 generator | `research/eval/generate_agent4_summary.py` |
| Agent 4 summary output | `summary_for_agent4.md` (generated; default `-o` for `generate_agent4_summary.py`) |
| Eval server | `mobile/lib/eval/eval_server.dart` |

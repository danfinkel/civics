# D01 prompt ablation lab

Self-contained workspace for running and analyzing **mobile `/infer`** experiments described in [`research/eval/README.md`](../eval/README.md). The inference driver stays in **`research/eval/runner.py`** (shared with the broader eval harness); this folder holds **experiment drivers**, **`results/`** JSONL archives, and the **analysis notebook**.

## Layout

| Path | Purpose |
|------|--------|
| `run_prompt_ablation.sh` | Run the standard 3-session ablation (generic → semantic → semantic-preview). Writes stamped JSONL files under `results/`. |
| `run_experiments.ipynb` | Jupyter driver: **one cell per scenario**, cooldown cells between sessions, PNGs saved for **markdown** figure cells under `results/figures/`. |
| `analysis.ipynb` | Load JSONL(s), summarize metrics, pivot by variant/prompt condition, plots. |
| `ablation_plots.py` | Plot helpers (`load_jsonl`, bar charts) shared by notebooks. |
| `results/` | Drop or generate `*.jsonl` artifacts here (`ablation_generic_*.jsonl`, etc.). |
| `requirements-notebook.txt` | Minimal deps for local analysis (`pandas`, plotting, Jupyter). Inference still needs [`../eval/requirements.txt`](../eval/requirements.txt) on the Mac that drives the phone. |

## Prerequisites for **running** experiments

1. **Civics repo** with **`research/artifacts/`** populated (same as `runner.py` expects).

### Setting up the iPhone (eval server)

The harness talks to on-device **`/infer`** over HTTP; that only exists in an **eval** build:

1. **Build with eval mode** — the iOS app must be compiled with **`EVAL_MODE=true`** so it starts the small HTTP server (port **8080**). Helper from repo root: **`mobile/scripts/dev_deploy.sh --eval`** (same story as [`research/eval/README.md`](../eval/README.md)).
2. **Run from Xcode onto the physical device** (Product → Run). Don’t rely on Simulator for this workflow unless your team explicitly supports it.
3. **Confirm the server is up** — in Xcode’s device/console logs look for **`Eval server running on port 8080`**. Until you see that, `runner.py` cannot reach **`/infer`**.
4. **Networking** — iPhone and Mac on the **same Wi‑Fi**; use the phone’s **LAN IP** (Settings → Wi‑Fi → info on the network → **IP Address**, e.g. `192.168.x.x`). This is **`PHONE_IP`**; base URL defaults to **`http://<PHONE_IP>:8080`**.
5. **Sanity check from the Mac**:

   ```bash
   curl "http://192.168.x.x:8080/health"
   ```

   Expect JSON including **`"status":"ok"`** (and loaded model identity). See the full checklist in **`research/eval/README.md`** § Prerequisites.
6. **During long runs** — keep the eval build reachable (foreground if your builds require it), avoid aggressive Low Power Mode if inference stalls, use **`CONDITION_BREAK_S`** between heavy sessions **for thermal breathing room**, and plug in between the three prompt conditions when possible.

Then on the **Mac**:

```bash
export PHONE_IP=192.168.x.x   # or PHONE_URL=http://...
cd research/prompt_ablation
./run_prompt_ablation.sh
```

**Between sessions**, the shell script waits **`CONDITION_BREAK_S`** (default **180** seconds unless `export CONDITION_BREAK_S=0`) — same guidance as [`run_week3_experiments.sh`](../eval/run_week3_experiments.sh).

Outputs land in **`results/ablation_<condition>_<YYYYMMDD_HHMM>.jsonl`** (three files per invocation).

For a **Markdown roll-up** (optional, same semantics as Agent-4 summaries), pass each JSONL explicitly (three files share one stamp after `./run_prompt_ablation.sh`):

```bash
cd ../eval
STAMP=20260412_1055
python3 generate_agent4_summary.py \
  "../prompt_ablation/results/ablation_generic_${STAMP}.jsonl" \
  "../prompt_ablation/results/ablation_semantic_${STAMP}.jsonl" \
  "../prompt_ablation/results/ablation_semantic_preview_${STAMP}.jsonl" \
  -o "../prompt_ablation/results/summary_${STAMP}.md"
```

## Analysis only (JSONL already on disk)

1. Install notebook deps:

   ```bash
   pip install -r requirements-notebook.txt
   ```

2. Open **`analysis.ipynb`**, set `JSONL_PATHS` to your file(s)—for example **`results/ablation_generic_20260412_1055.jsonl`**.
3. Or open **`run_experiments.ipynb`**: set **`STAMP`** in the config cell to match existing `ablation_generic_<STAMP>.jsonl` / `ablation_semantic_<STAMP>.jsonl` if you only want to **refresh figures** (`RUN_EXPERIMENTS = False`).

The analysis notebook resolves **repository root**, adds **`research/eval`** to `sys.path`, and imports **`compute_summary`** from **`runner`** so percentages match the CLI harness.

## Migrating older JSONLs

Previous runs may live under `research/eval/results/` or nested folders (e.g. `ablation_results/`). Safe approach:

```bash
cp research/eval/results/ablation_results/ablation_generic_*.jsonl research/prompt_ablation/results/
```

No need to change file contents—the schema is defined by **`runner.py`** row payloads.

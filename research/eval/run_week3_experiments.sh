#!/usr/bin/env bash
# Week 3 Agent 2 — experiment drivers (agent2_wed_fri_plan + prompt ablation).
# Prerequisites: iPhone on same Wi‑Fi, model on device, eval build running.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ -z "${PHONE_IP:-}" && -z "${PHONE_URL:-}" ]]; then
  echo "Set PHONE_IP (e.g. export PHONE_IP=192.168.1.x) or PHONE_URL before running."
  exit 1
fi

STEP="${1:-}"
STAMP="$(date +%Y%m%d_%H%M)"
# Cooldown between separate runner processes (thermal / memory). Override: export CONDITION_BREAK_S=0
CONDITION_BREAK_S="${CONDITION_BREAK_S:-180}"

condition_break_countdown() {
  local sec="${1:?seconds}"
  if (( sec <= 0 )); then
    return 0
  fi
  echo ""
  echo "Condition break: waiting ${sec}s before next runner session..."
  local r
  for (( r = sec; r > 0; r-- )); do
    printf "\r  Condition break: %3ds remaining... " "$r"
    sleep 1
  done
  printf "\r  Condition break: done.                    \n"
}

# Primary paper experiment: one Python process per prompt condition → separate JSONL files.
# Order: generic → semantic → semantic-preview (run preview last per ops guidance).
run_prompt_ablation() {
  echo "=== PRIMARY: D01 prompt ablation — 3 sessions × 4 variants × 20 runs = 80 rows/file ==="
  echo "Outputs: results/ablation_{generic,semantic,semantic_preview}_${STAMP}.jsonl"
  python3 runner.py \
    --artifacts D01 \
    --track a \
    --variants clean,clean_jpeg,degraded,blurry \
    --prompt-condition generic \
    --runs 20 \
    --temp 0.0 \
    --cooldown 2.0 \
    --condition-break-s 0 \
    --out "results/ablation_generic_${STAMP}.jsonl"

  condition_break_countdown "${CONDITION_BREAK_S}"

  python3 runner.py \
    --artifacts D01 \
    --track a \
    --variants clean,clean_jpeg,degraded,blurry \
    --prompt-condition semantic \
    --runs 20 \
    --temp 0.0 \
    --cooldown 2.0 \
    --condition-break-s 0 \
    --out "results/ablation_semantic_${STAMP}.jsonl"

  condition_break_countdown "${CONDITION_BREAK_S}"

  echo "Starting semantic-preview (run only after phone idle/charging ≥10m if possible)."
  python3 runner.py \
    --artifacts D01 \
    --track a \
    --variants clean,clean_jpeg,degraded,blurry \
    --prompt-condition semantic-preview \
    --runs 20 \
    --temp 0.0 \
    --cooldown 2.0 \
    --condition-break-s 0 \
    --out "results/ablation_semantic_preview_${STAMP}.jsonl"
}

# Five generic/clean runs with full raw text to stdout (investigate clean-PDF path).
run_prompt_ablation_probe_generic_clean() {
  echo "=== PROBE: 5× generic / clean — raw responses printed ==="
  python3 runner.py \
    --artifacts D01 \
    --track a \
    --variants clean \
    --prompt-condition generic \
    --runs 5 \
    --temp 0.0 \
    --cooldown 2.0 \
    --print-raw-response \
    --out "results/probe_generic_clean_${STAMP}.jsonl"
}

run_baseline() {
  echo "=== Legacy baseline: D01/D03, clean+degraded, 20 runs ==="
  python3 runner.py \
    --artifacts D01,D03 \
    --track a \
    --variants clean,degraded \
    --runs 20 \
    --temp 0.0 \
    --cooldown 2.0 \
    --out "results/d01_d03_baseline_${STAMP}.jsonl"
}

# Secondary: output-token budget sweep (unchanged).
run_token_ablation() {
  echo "=== SECONDARY: D03 token budget ablation ==="
  python3 runner.py \
    --artifacts D03 \
    --track a \
    --variants clean,degraded \
    --runs 10 \
    --temp 0.0 \
    --token-budgets 70,140,280,560,1120 \
    --ablation \
    --cooldown 3.0 \
    --out "results/token_budget_ablation_${STAMP}.jsonl"
}

run_thermal() {
  echo "=== Thermal: D01,D03,D04 degraded, 30 runs + metrics poll ==="
  python3 runner.py \
    --artifacts D01,D03,D04 \
    --track a \
    --variants degraded \
    --runs 30 \
    --temp 0.0 \
    --cooldown 1.0 \
    --metrics-log "results/thermal_metrics_${STAMP}.jsonl" \
    --metrics-interval 30 \
    --out "results/thermal_test_${STAMP}.jsonl"
  echo "Plot: python3 plot_run_latency.py results/thermal_test_${STAMP}.jsonl -o results/thermal_latency_${STAMP}.png"
}

case "$STEP" in
  prompt-ablation) run_prompt_ablation ;;
  prompt-ablation-probe) run_prompt_ablation_probe_generic_clean ;;
  baseline) run_baseline ;;
  token-ablation) run_token_ablation ;;
  ablation) run_token_ablation ;; # alias
  thermal) run_thermal ;;
  all)
    run_prompt_ablation
    run_token_ablation
    run_thermal
    ;;
  *)
    echo "Usage: $0 {prompt-ablation|prompt-ablation-probe|baseline|token-ablation|thermal|all}"
    echo ""
    echo "  prompt-ablation       — PRIMARY: 3 separate JSONLs (generic → semantic → semantic-preview)"
    echo "  prompt-ablation-probe — 5× generic/clean + print-raw-response (diagnostics)"
    echo "  baseline              — D01/D03 JSONL baseline (GT-shaped prompts)"
    echo "  token-ablation        — SECONDARY D03 max-token sweep"
    echo "  thermal               — long run + /metrics JSONL"
    echo "  all                   — prompt ablation, then token ablation, then thermal"
    echo ""
    echo "Between prompt-ablation sessions: CONDITION_BREAK_S (default 180) second countdown."
    exit 1
    ;;
esac

echo "Agent 4 summary: python3 generate_agent4_summary.py results/<your>.jsonl -o summary_for_agent4.md"

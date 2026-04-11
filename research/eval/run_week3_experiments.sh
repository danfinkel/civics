#!/usr/bin/env bash
# Week 3 Agent 2 — Wed–Fri experiment commands (agent2_wed_fri_plan.md).
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

run_baseline() {
  echo "=== Wednesday baseline: D01/D03, clean+degraded, 20 runs ==="
  python3 runner.py \
    --artifacts D01,D03 \
    --track a \
    --variants clean,degraded \
    --runs 20 \
    --temp 0.0 \
    --cooldown 2.0 \
    --out "results/d01_d03_baseline_${STAMP}.jsonl"
}

run_ablation() {
  echo "=== Thursday ablation: D03 token budgets ==="
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
  echo "=== Friday thermal: D01,D03,D04 degraded, 30 runs + metrics poll ==="
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
  baseline) run_baseline ;;
  ablation) run_ablation ;;
  thermal) run_thermal ;;
  all)
    run_baseline
    run_ablation
    run_thermal
    ;;
  *)
    echo "Usage: $0 {baseline|ablation|thermal|all}"
    echo ""
    echo "  baseline — Wed: D01/D03 Monte Carlo"
    echo "  ablation — Thu: D03 token budgets"
    echo "  thermal  — Fri: extended run + /metrics JSONL"
    echo "  all      — run all three in sequence (long session)"
    exit 1
    ;;
esac

echo "Agent 4 summary (after runs): python3 generate_agent4_summary.py results/<your>.jsonl -o summary_for_agent4.md"

#!/usr/bin/env bash
# D01 prompt ablation — three JSONL artifacts under research/prompt_ablation/results/.
# Mirrors research/eval/run_week3_experiments.sh prompt-ablation, with standalone output paths.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EVAL_DIR="$REPO_ROOT/research/eval"
OUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/results"
cd "$EVAL_DIR"

if [[ -z "${PHONE_IP:-}" && -z "${PHONE_URL:-}" ]]; then
  echo "Set PHONE_IP (e.g. export PHONE_IP=192.168.1.x) or PHONE_URL before running."
  exit 1
fi

STAMP="$(date +%Y%m%d_%H%M)"
mkdir -p "$OUT_DIR"

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

echo "=== D01 prompt ablation — outputs in $OUT_DIR ==="
echo "Stamp: ${STAMP}"

python3 runner.py \
  --artifacts D01 \
  --track a \
  --variants clean,clean_jpeg,degraded,blurry \
  --prompt-condition generic \
  --runs 20 \
  --temp 0.0 \
  --cooldown 2.0 \
  --condition-break-s 0 \
  --out "$OUT_DIR/ablation_generic_${STAMP}.jsonl"

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
  --out "$OUT_DIR/ablation_semantic_${STAMP}.jsonl"

condition_break_countdown "${CONDITION_BREAK_S}"

echo "Starting semantic-preview (prefer phone idle/charging briefly before load)."
python3 runner.py \
  --artifacts D01 \
  --track a \
  --variants clean,clean_jpeg,degraded,blurry \
  --prompt-condition semantic-preview \
  --runs 20 \
  --temp 0.0 \
  --cooldown 2.0 \
  --condition-break-s 0 \
  --out "$OUT_DIR/ablation_semantic_preview_${STAMP}.jsonl"

echo ""
echo "Done. Next: open research/prompt_ablation/analysis.ipynb or run:"
echo "  cd \"$EVAL_DIR\" && python3 generate_agent4_summary.py \\"
echo "    \"$OUT_DIR/ablation_generic_${STAMP}.jsonl\" \\"
echo "    \"$OUT_DIR/ablation_semantic_${STAMP}.jsonl\" \\"
echo "    \"$OUT_DIR/ablation_semantic_preview_${STAMP}.jsonl\" \\"
echo "    -o \"$OUT_DIR/summary_${STAMP}.md\""

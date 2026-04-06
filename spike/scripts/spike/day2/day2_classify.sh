#!/bin/bash
# Day 2 Step 1 — Document Classification runner
# Usage: ./day2_classify.sh [artifact_ids]
# Example: ./day2_classify.sh D01,D03,D05

set -e

cd "$(dirname "$0")"

ARTIFACTS="${1:-}"
MODEL="${MODEL:-gemma4:e4b}"
RUNS="${RUNS:-1}"

echo "Day 2 Step 1: Document Classification"
echo "Model: $MODEL"
echo "Runs per artifact: $RUNS"
echo ""

if [ -n "$ARTIFACTS" ]; then
    echo "Running classification for: $ARTIFACTS"
    python day2_classify.py \
        --artifacts "$ARTIFACTS" \
        --model "$MODEL" \
        --runs "$RUNS" \
        --variants degraded
else
    echo "Running classification for all 16 artifacts"
    python day2_classify.py \
        --model "$MODEL" \
        --runs "$RUNS" \
        --variants degraded
fi

echo ""
echo "Classification complete. Results: day2_classification_results.jsonl"
echo "Run ./day2_summarize.sh to view summary."

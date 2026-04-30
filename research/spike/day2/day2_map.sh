#!/bin/bash
# Day 2 Step 2 — Category Mapping runner
# Usage: ./day2_map.sh [artifact_ids]
# Example: ./day2_map.sh D04,D05,D06

set -e

cd "$(dirname "$0")"

ARTIFACTS="${1:-}"
MODEL="${MODEL:-gemma4:e4b}"
RUNS="${RUNS:-1}"

echo "Day 2 Step 2: Category Mapping"
echo "Model: $MODEL"
echo "Runs per artifact: $RUNS"
echo ""

if [ -n "$ARTIFACTS" ]; then
    echo "Running mapping for: $ARTIFACTS"
    python day2_map.py \
        --artifacts "$ARTIFACTS" \
        --model "$MODEL" \
        --runs "$RUNS" \
        --variants clean,degraded
else
    echo "Running mapping for all 8 mapping artifacts"
    python day2_map.py \
        --model "$MODEL" \
        --runs "$RUNS" \
        --variants clean,degraded
fi

echo ""
echo "Mapping complete. Results: day2_mapping_results.jsonl"
echo "Run ./day2_summarize.sh to view summary."

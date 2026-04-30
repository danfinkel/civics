#!/bin/bash
# Day 2 — Summarize results from classification and mapping

cd "$(dirname "$0")"

echo "Day 2 Summary"
echo "============="
echo ""

python day2_summarize.py \
    --classification day2_classification_results.jsonl \
    --mapping day2_mapping_results.jsonl

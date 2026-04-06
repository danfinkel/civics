#!/bin/bash
# Day 3 Track B — BPS Packet Checker runner
#
# Usage:
#   ./day3_track_b.sh           # Run all 8 scenarios
#   ./day3_track_b.sh B1,B2     # Run specific scenarios
#   ./day3_track_b.sh --summarize  # Show summary of existing results

set -e

cd "$(dirname "$0")"

if [ "$1" = "--summarize" ]; then
    echo "Summarizing Track B results..."
    python3 day3_track_b_summarize.py day3_track_b_results.jsonl
    exit 0
fi

SCENARIOS="${1:-}"

echo "Running Day 3 Track B — BPS Packet Checker"
echo "============================================"

if [ -n "$SCENARIOS" ]; then
    echo "Scenarios: $SCENARIOS"
    python3 day3_track_b.py --scenarios "$SCENARIOS"
else
    echo "Scenarios: all 8 (B1-B8)"
    python3 day3_track_b.py
fi

echo ""
echo "Summary:"
python3 day3_track_b_summarize.py day3_track_b_results.jsonl

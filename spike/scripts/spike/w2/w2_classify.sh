#!/usr/bin/env bash
# W2 classification: D01 + D03, clean PDFs and degraded JPGs (5 runs each via w2_classify.py).
set -euo pipefail
SPIKE="$(cd "$(dirname "$0")/../.." && pwd)"
exec python "$SPIKE/scripts/w2/w2_classify.py" \
  "$SPIKE/artifacts/clean/D01.pdf" \
  "$SPIKE/artifacts/degraded/D01-degraded.jpg" \
  "$SPIKE/artifacts/clean/D03.pdf" \
  "$SPIKE/artifacts/degraded/D03-degraded.jpg"

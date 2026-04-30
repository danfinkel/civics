#!/usr/bin/env bash
# Local Track A pipeline (OCR + mobile-matched prompt + Ollama text-only).
# Repo root: civics/  (parent of research/)
#
#   ./research/spike/track_a_mobile_local.sh research/artifacts/degraded/D01-degraded.jpg \
#     research/artifacts/degraded/D03-degraded.jpg research/artifacts/degraded/D06-degraded.jpg
#
#   ./research/spike/track_a_mobile_local.sh --no-llm \
#     research/artifacts/degraded/D01-degraded.jpg research/artifacts/degraded/D03-degraded.jpg
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"
if [[ -x "${ROOT}/.venv/bin/python" ]]; then
  exec "${ROOT}/.venv/bin/python" -u research/spike/track_a_mobile_local.py "$@"
else
  exec uv run --group dev python research/spike/track_a_mobile_local.py "$@"
fi

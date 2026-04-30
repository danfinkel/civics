#!/usr/bin/env bash
# W4 proof matching: EARNED INCOME category × three documents, 5 runs each.
#
# Pairings (expected behaviors — verify in output):
#   D03.pdf (clean pay stub)     → likely_satisfies, high confidence
#   D03-degraded.jpg             → likely_satisfies, medium confidence
#   D01.pdf (government notice)  → likely_does_not_satisfy (not acceptable income proof)
#
# Repo uses artifacts/clean/D03.pdf (same as "D03-clean.pdf" in the experiment write-up).
#
# Uses civics uv env when available; see w3_abstention.sh for fallbacks.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPIKE="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROOT="$(cd "$SPIKE/.." && pwd)"
PY_SCRIPT="$SPIKE/scripts/w4/w4_match.py"

ec=0
if command -v uv >/dev/null 2>&1 && [[ -f "$ROOT/pyproject.toml" ]]; then
  (cd "$ROOT" && uv run --group dev python "$PY_SCRIPT" \
    "$SPIKE/artifacts/clean/D03.pdf" \
    "$SPIKE/artifacts/degraded/D03-degraded.jpg" \
    "$SPIKE/artifacts/clean/D01.pdf") || ec=$?
elif command -v python3 >/dev/null 2>&1; then
  python3 "$PY_SCRIPT" \
    "$SPIKE/artifacts/clean/D03.pdf" \
    "$SPIKE/artifacts/degraded/D03-degraded.jpg" \
    "$SPIKE/artifacts/clean/D01.pdf" || ec=$?
elif command -v python >/dev/null 2>&1; then
  python "$PY_SCRIPT" \
    "$SPIKE/artifacts/clean/D03.pdf" \
    "$SPIKE/artifacts/degraded/D03-degraded.jpg" \
    "$SPIKE/artifacts/clean/D01.pdf" || ec=$?
else
  echo "Error: need uv (recommended) or python3 on PATH." >&2
  exit 127
fi

if [[ "$ec" -ne 0 ]]; then
  echo "" >&2
  echo "w4_match.sh failed with exit code $ec" >&2
fi

if [[ -n "${W4_PAUSE:-}" ]]; then
  read -rp "Press Enter to close this window... " _ || true
fi

exit "$ec"

#!/usr/bin/env bash
# W3 abstention: D01-blurry only (~bottom 28% darkened). 5 runs via w3_abstention.py.
#
# Uses the civics repo uv env (ollama + Pillow) when possible. Fallback: python3/python.
# If a Terminal window closes before you can read errors: run from Terminal, or
#   W3_PAUSE=1 ./w3_abstention.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPIKE="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROOT="$(cd "$SPIKE/.." && pwd)"
IMG="$SPIKE/artifacts/clean/D01-blurry.jpg"
PY_SCRIPT="$SPIKE/scripts/w3/w3_abstention.py"

ec=0
if command -v uv >/dev/null 2>&1 && [[ -f "$ROOT/pyproject.toml" ]]; then
  (cd "$ROOT" && uv run --group dev python "$PY_SCRIPT" "$IMG") || ec=$?
elif command -v python3 >/dev/null 2>&1; then
  python3 "$PY_SCRIPT" "$IMG" || ec=$?
elif command -v python >/dev/null 2>&1; then
  python "$PY_SCRIPT" "$IMG" || ec=$?
else
  echo "Error: need uv (recommended, from repo root) or python3 on PATH." >&2
  exit 127
fi

if [[ "$ec" -ne 0 ]]; then
  echo "" >&2
  echo "w3_abstention.sh failed with exit code $ec" >&2
fi

if [[ -n "${W3_PAUSE:-}" ]]; then
  read -rp "Press Enter to close this window... " _ || true
fi

exit "$ec"

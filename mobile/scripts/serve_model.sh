#!/usr/bin/env bash
# Serve Gemma GGUF over HTTP (port 8888) with GET /health for dev_deploy checks.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOBILE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PORT="${PORT:-8888}"
HOST="${HOST:-0.0.0.0}"

# Resolve model path: MODEL_PATH env, then common locations
MODEL_PATH="${MODEL_PATH:-}"
if [[ -z "$MODEL_PATH" ]]; then
  for candidate in \
    "$MOBILE_DIR/ios/gemma-4-E2B-it-Q4_K_M.gguf" \
    "$MOBILE_DIR/assets/models/gemma-4-E2B-it-Q4_K_M.gguf" \
    "$HOME/Downloads/gemma-4-E2B-it-Q4_K_M.gguf"
  do
    if [[ -f "$candidate" ]]; then
      MODEL_PATH="$candidate"
      break
    fi
  done
fi

if [[ -z "$MODEL_PATH" || ! -f "$MODEL_PATH" ]]; then
  echo "ERROR: GGUF not found. Set MODEL_PATH to gemma-4-E2B-it-Q4_K_M.gguf"
  echo "  Searched: ios/, assets/models/, ~/Downloads/"
  exit 1
fi

echo "Using model: $MODEL_PATH"
echo ""
echo "Wi‑Fi: iPhone must be on the same network as this Mac."
echo "       Use your Mac's IP in MODEL_SERVER_URL when running dev_deploy.sh"
echo "       (localhost/127.0.0.1 only works for the simulator on this machine)."
echo ""

exec python3 "$SCRIPT_DIR/serve_model_http.py" --host "$HOST" --port "$PORT" --file "$MODEL_PATH"

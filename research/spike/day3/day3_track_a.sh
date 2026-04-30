#!/usr/bin/env bash
# Day 3 Track A — SNAP Proof-Pack Builder
# Run from repo root: ollama + dev deps (pillow, pdf2image).
set -euo pipefail
# Get script directory reliably
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
cd "$ROOT"
# Prefer project venv; -u = unbuffered stdout for live progress.
exec "${ROOT}/.venv/bin/python" -u spike/scripts/spike/day3/day3_track_a.py "$@"

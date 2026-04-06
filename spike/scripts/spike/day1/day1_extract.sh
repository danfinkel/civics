#!/usr/bin/env bash
# Day 1 extraction batch — run from repo root: ollama + dev deps (pillow, pdf2image).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
# Prefer project venv; -u = unbuffered stdout for live progress.
exec "${ROOT}/.venv/bin/python" -u spike/scripts/day1/day1_extract.py "$@"

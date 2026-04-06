#!/usr/bin/env bash
# Render synthetic HTML artifacts to PDF using Chrome headless (macOS / Chrome default path).
# Requires network on first run so @import Google Fonts can load.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HTML_DIR="$SCRIPT_DIR/../../artifacts/clean/html"
OUT_DIR="$SCRIPT_DIR/../../artifacts/clean"

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
if [[ ! -x "$CHROME" ]]; then
  echo "Chrome not found at: $CHROME" >&2
  echo "Set CHROME to your browser binary, or install Google Chrome." >&2
  exit 1
fi

shopt -s nullglob
files=("$HTML_DIR"/*-clean.html)
if [[ ${#files[@]} -eq 0 ]]; then
  echo "No *-clean.html files under $HTML_DIR" >&2
  exit 1
fi

for html in "${files[@]}"; do
  base="$(basename "$html" .html)"
  pdf="$OUT_DIR/${base}.pdf"
  uri="file://$(python3 -c "import pathlib; print(pathlib.Path(r'''$html''').resolve().as_posix())")"
  echo "→ $base.pdf"
  "$CHROME" --headless=new --disable-gpu --no-pdf-header-footer \
    --print-to-pdf="$pdf" "$uri" 2>/dev/null
done

echo "Done. PDFs in $OUT_DIR"

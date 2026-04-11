#!/usr/bin/env bash
# Lists demo images for human QA / recordings; copies from repo when present.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MOBILE_ASSETS="$SCRIPT_DIR/../assets/test_docs"
SPIKE_DIR="$REPO_ROOT/spike/artifacts"

# Track A / B demo filenames (from week3 plan; some may not exist yet)
declare -a WANT=(
  "D01-degraded.jpg"
  "D03-degraded.jpg"
  "D04-degraded.jpg"
  "D05-degraded.jpg"
  "D06-degraded.jpg"
  "D07-degraded.jpg"
  "D12-degraded.jpg"
  "D13-degraded.jpg"
  "D14-degraded.jpg"
  "D01-blurry.jpg"
)

echo "=== sync_test_assets — demo image checklist ==="
echo "Target Photos library: manual (see instructions below)."
echo ""

SYNCED=0
MISSING=0

for f in "${WANT[@]}"; do
  found=""
  for dir in "$MOBILE_ASSETS" "$SPIKE_DIR" "$SPIKE_DIR/clean" "$SPIKE_DIR/degraded"; do
    if [[ -f "$dir/$f" ]]; then
      found="$dir/$f"
      break
    fi
  done
  # Also accept non-degraded names already in test_docs (D12.jpg, etc.)
  if [[ -z "$found" ]]; then
    base="${f%-degraded.jpg}"
    base="${base%-blurry.jpg}"
    for ext in jpg jpeg png; do
      if [[ -f "$MOBILE_ASSETS/${base}.$ext" ]]; then
        found="$MOBILE_ASSETS/${base}.$ext"
        break
      fi
    done
  fi

  if [[ -n "$found" ]]; then
    echo "  [in repo] $f  ←  $found"
    SYNCED=$((SYNCED + 1))
  else
    echo "  [missing] $f"
    MISSING=$((MISSING + 1))
  fi
done

echo ""
echo "Summary: $SYNCED matched in repo, $MISSING not found (generate or add under spike/ or assets/test_docs/)."
echo ""

echo "=== Import to iPhone Photos (manual) ==="
echo "1. AirDrop or Files: copy JPGs to the device."
echo "2. Or macOS Photos: import folder, enable iCloud Photos on the phone."
echo "3. Optional — Image Capture: connect iPhone, run:"
echo "     osascript -e 'tell application \"Image Capture\" to activate'"
echo "   (Scripting Image Capture paths is device-specific; use UI if automation fails.)"
echo ""
echo "After import, use Library picker in CivicLens for School Enrollment / SNAP flows."

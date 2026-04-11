# CivicLens — Week 3 Agent Plans
## April 14–18, 2026

**Sprint goal:** Demo-ready app, video recorded, eval infrastructure running, repo foundation laid.

**Context for all agents:** We are 5 weeks from the May 18 submission deadline with a working on-device demo (15.3s pipeline, iPhone 16, Gemma 4 E2B). Week 3 has three parallel workstreams: demo polish, eval infrastructure, and research foundation. All agents should write code and documentation as if this project will continue after the hackathon and be cited in academic papers.

**North star story:** A resident receives a government notice, photographs their documents at home, and the app tells them whether what they have is sufficient — before they show up somewhere and are turned away. The RMV real-ID scenario is the anchor: wrong document, wasted trip, avoidable with a 15-second check.

---

## Agent 1 — App Quality Audit and Track A Demo Polish

**Owns:** `mobile/lib/features/`, `mobile/lib/shared/`, `mobile/scripts/`, demo flow end-to-end

**Primary goal:** Make the app demo-ready. No rough edges, no exposed wires, graceful handling of every state. By Friday: hand someone the phone, they can complete both the D01/D03 Track A scenario and the B4 Track B scenario without any guidance from you.

**QA approach — hybrid (automated + human):** AI agents cannot see a running app on a physical device. The audit is therefore split into two phases: Agent 1 does everything that can be verified by reading code (static analysis, string search, widget tests, golden screenshots on simulator), then the human does one focused walkthrough on device using the checklist below and feeds findings back to Agent 1 for fixes. This is the fastest path to a polished demo.

---

### Part 1: Dev Workflow Script — Build, Install, Model Download

**Build this first.** Before any QA work, give the human a single script that handles the full rebuild-reinstall-model cycle. This eliminates the friction of manual Xcode steps between fix iterations and is the most direct way to accelerate your on-device testing loop.

**Create `mobile/scripts/dev_deploy.sh`:**

```bash
#!/bin/bash
# CivicLens dev deploy script
# Rebuilds the app, installs on connected iPhone, and ensures model is present.
#
# Usage:
#   ./scripts/dev_deploy.sh                    # build + install, skip model if present
#   ./scripts/dev_deploy.sh --force-model      # force re-download model
#   ./scripts/dev_deploy.sh --release          # release build (slower compile, faster runtime)
#   ./scripts/dev_deploy.sh --eval             # launch in eval mode (inference server on :8080)
#
# Prerequisites:
#   - iPhone connected via USB and trusted
#   - flutter, xcrun in PATH
#   - DEVICE_ID set in environment OR script auto-detects single connected device
#
# Model hosting: The Gemma 4 E2B Q4_K_M GGUF (2.9GB) is served from a local
# HTTP server during development. In production the app downloads from HuggingFace.
# Set MODEL_SERVER_URL below to point at your local server.

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOBILE_DIR="$(dirname "$SCRIPT_DIR")"
MODEL_FILENAME="gemma-4-e2b-it-q4_k_m.gguf"
MODEL_SERVER_URL="${MODEL_SERVER_URL:-http://localhost:8888}"
MODEL_LOCAL_PATH="$MOBILE_DIR/assets/models/$MODEL_FILENAME"

# Build flags
BUILD_MODE="debug"
EVAL_MODE=false
FORCE_MODEL=false

# Parse args
for arg in "$@"; do
  case $arg in
    --release)    BUILD_MODE="release" ;;
    --eval)       EVAL_MODE=true ;;
    --force-model) FORCE_MODEL=true ;;
  esac
done

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'; BOLD='\033[1m'

log()  { echo -e "${BLUE}▶${NC} $1"; }
ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }

# ── Step 1: Find device ───────────────────────────────────────────────────────
log "Finding connected iPhone..."

if [ -n "${DEVICE_ID:-}" ]; then
  ok "Using DEVICE_ID from environment: $DEVICE_ID"
else
  DEVICE_LIST=$(flutter devices --machine 2>/dev/null | \
    python3 -c "
import json, sys
devices = json.load(sys.stdin)
iphones = [d for d in devices if d.get('targetPlatform') == 'ios' and not d.get('emulator', False)]
for d in iphones:
    print(d['id'], d['name'])
" 2>/dev/null || echo "")

  DEVICE_COUNT=$(echo "$DEVICE_LIST" | grep -c . || echo "0")
  
  if [ "$DEVICE_COUNT" -eq 0 ]; then
    fail "No iPhone found. Connect your iPhone via USB and trust this computer."
  elif [ "$DEVICE_COUNT" -gt 1 ]; then
    warn "Multiple iPhones found:"
    echo "$DEVICE_LIST"
    fail "Set DEVICE_ID=<id> to specify which device, e.g: DEVICE_ID=00008120-... ./scripts/dev_deploy.sh"
  else
    DEVICE_ID=$(echo "$DEVICE_LIST" | awk '{print $1}')
    DEVICE_NAME=$(echo "$DEVICE_LIST" | cut -d' ' -f2-)
    ok "Found: $DEVICE_NAME ($DEVICE_ID)"
  fi
fi

# ── Step 2: Check model ───────────────────────────────────────────────────────
log "Checking Gemma 4 E2B model..."

# The model lives in the app's Documents directory on device.
# We check for it via a simple marker file and re-download if missing or forced.
MODEL_MARKER="$MOBILE_DIR/.model_downloaded"

if [ "$FORCE_MODEL" = true ]; then
  rm -f "$MODEL_MARKER"
  warn "Force re-download requested"
fi

if [ ! -f "$MODEL_MARKER" ]; then
  log "Model not found locally. Starting download server check..."
  
  # Check if local model server is running
  if curl -sf "$MODEL_SERVER_URL/health" > /dev/null 2>&1; then
    ok "Local model server found at $MODEL_SERVER_URL"
    warn "Model will be downloaded to device on first app launch."
    warn "Make sure your iPhone and Mac are on the same WiFi network."
    warn "The app will show a download progress screen (~3 min on WiFi)."
    
    # Write the server URL into the app config so it knows where to download from
    cat > "$MOBILE_DIR/lib/core/config/model_config.dart" << EOF
// Auto-generated by dev_deploy.sh — do not edit manually
// This file is gitignored; production uses HuggingFace URL
const String kModelDownloadUrl = '$MODEL_SERVER_URL/$MODEL_FILENAME';
const String kModelFilename = '$MODEL_FILENAME';
EOF
    touch "$MODEL_MARKER"
    ok "Model config written"
  else
    warn "Local model server not running at $MODEL_SERVER_URL"
    warn "App will fall back to HuggingFace download (slower, requires internet)"
    warn "To start local server: cd /path/to/models && python3 -m http.server 8888"
  fi
else
  ok "Model marker present — skipping download setup"
fi

# ── Step 3: Flutter clean (conditional) ──────────────────────────────────────
cd "$MOBILE_DIR"

# Only clean if pubspec.yaml changed since last build
# This avoids the slow clean on every iteration
PUBSPEC_HASH_FILE="$MOBILE_DIR/.pubspec_hash"
CURRENT_HASH=$(md5 -q pubspec.yaml 2>/dev/null || md5sum pubspec.yaml | cut -d' ' -f1)
STORED_HASH=$(cat "$PUBSPEC_HASH_FILE" 2>/dev/null || echo "")

if [ "$CURRENT_HASH" != "$STORED_HASH" ]; then
  log "pubspec.yaml changed — running flutter clean..."
  flutter clean
  flutter pub get
  echo "$CURRENT_HASH" > "$PUBSPEC_HASH_FILE"
  ok "Dependencies refreshed"
else
  ok "pubspec.yaml unchanged — skipping clean (faster rebuild)"
fi

# ── Step 4: Build ─────────────────────────────────────────────────────────────
log "Building CivicLens ($BUILD_MODE)..."

BUILD_ARGS="--$BUILD_MODE -d $DEVICE_ID"

if [ "$EVAL_MODE" = true ]; then
  BUILD_ARGS="$BUILD_ARGS --dart-define=EVAL_MODE=true"
  warn "Building in EVAL MODE — inference server will run on :8080"
fi

START_TIME=$(date +%s)

flutter run $BUILD_ARGS \
  --dart-define=APP_VERSION=$(cat version.txt 2>/dev/null || echo "dev") \
  2>&1 | tee /tmp/civiclens_build.log | grep -E "(Running|Installing|Syncing|error:|warning:|✓|✗|Launched)" || true

END_TIME=$(date +%s)
BUILD_SECONDS=$((END_TIME - START_TIME))

# Check if build succeeded
if grep -q "error:" /tmp/civiclens_build.log; then
  echo ""
  fail "Build failed. See errors above. Full log: /tmp/civiclens_build.log"
fi

ok "Build complete in ${BUILD_SECONDS}s"

# ── Step 5: Post-install summary ──────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  CivicLens installed successfully${NC}"
echo -e "${BOLD}═══════════════════════════════════════${NC}"
echo ""
echo -e "  Device:  $DEVICE_NAME"
echo -e "  Mode:    $BUILD_MODE"
if [ "$EVAL_MODE" = true ]; then
echo -e "  ${YELLOW}Eval:    Inference server on :8080${NC}"
echo -e "  ${YELLOW}         Run: python research/eval/runner.py${NC}"
fi
echo ""
echo -e "  ${BLUE}Test files ready in Photos app:${NC}"
echo -e "  D01-degraded.jpg  D03-degraded.jpg  (Track A demo)"
echo -e "  D05-degraded.jpg  D14-degraded.jpg  (Track B B4 demo)"
echo ""
echo -e "  ${BLUE}Audit checklist:${NC} docs/sprint/week3_audit.md"
echo ""
```

**Make it executable and add companion scripts:**

```bash
chmod +x mobile/scripts/dev_deploy.sh

# Convenience aliases to add to README:
# alias civiclens-deploy='cd /path/to/civiclens && ./mobile/scripts/dev_deploy.sh'
# alias civiclens-eval='cd /path/to/civiclens && ./mobile/scripts/dev_deploy.sh --eval'
# alias civiclens-release='cd /path/to/civiclens && ./mobile/scripts/dev_deploy.sh --release'
```

**Create `mobile/scripts/serve_model.sh`** — starts the local model HTTP server for fast development downloads:

```bash
#!/bin/bash
# Serves the Gemma 4 E2B model file over HTTP for fast on-device downloads.
# Much faster than downloading from HuggingFace during development.
#
# Usage: ./scripts/serve_model.sh /path/to/models/directory
#
# The models directory should contain:
#   gemma-4-e2b-it-q4_k_m.gguf  (2.9GB)

set -euo pipefail

MODEL_DIR="${1:-$HOME/models}"

if [ ! -d "$MODEL_DIR" ]; then
  echo "Error: Model directory not found: $MODEL_DIR"
  echo "Usage: ./scripts/serve_model.sh /path/to/models"
  exit 1
fi

MODEL_FILE="$MODEL_DIR/gemma-4-e2b-it-q4_k_m.gguf"
if [ ! -f "$MODEL_FILE" ]; then
  echo "Model file not found: $MODEL_FILE"
  echo ""
  echo "Download it first:"
  echo "  pip install huggingface_hub"
  echo "  huggingface-cli download bartowski/gemma-4-e2b-it-GGUF \\"
  echo "    gemma-4-e2b-it-q4_k_m.gguf --local-dir $MODEL_DIR"
  exit 1
fi

MODEL_SIZE=$(du -sh "$MODEL_FILE" | cut -f1)
echo "Serving $MODEL_FILE ($MODEL_SIZE) on http://0.0.0.0:8888"
echo "Make sure your iPhone and Mac are on the same WiFi network."
echo "Press Ctrl+C to stop."
echo ""

# Add health endpoint via a tiny wrapper
python3 - <<'PYEOF'
import http.server
import os
import sys
import json

class ModelServer(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'ok'}).encode())
        else:
            super().do_GET()
    
    def log_message(self, format, *args):
        # Show download progress
        if '206' in str(args) or '200' in str(args):
            sys.stderr.write(f"  → {args[0]} {args[1]}\n")

os.chdir(sys.argv[1] if len(sys.argv) > 1 else '.')
with http.server.HTTPServer(('0.0.0.0', 8888), ModelServer) as httpd:
    httpd.serve_forever()
PYEOF
```

**Create `mobile/scripts/sync_test_assets.sh`** — copies spike test images to the iPhone Photos app so they're ready to select during manual testing:

```bash
#!/bin/bash
# Copies spike test images to iPhone for manual QA testing.
# After running this, the images will be available in the Photos app
# when you tap "Choose from Library" in CivicLens.
#
# Usage: ./scripts/sync_test_assets.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIKE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")/spike/artifacts"

# Images needed for demo scenarios
DEMO_IMAGES=(
  "degraded/D01-degraded.jpg"   # Track A: SNAP notice
  "degraded/D03-degraded.jpg"   # Track A: Pay stub
  "degraded/D04-degraded.jpg"   # Track A: Stale pay stub
  "degraded/D05-degraded.jpg"   # Track B: Lease 1
  "degraded/D06-degraded.jpg"   # Track B: Utility bill
  "degraded/D07-degraded.jpg"   # Track B: Phone bill
  "degraded/D12-degraded.jpg"   # Track B: Birth certificate
  "degraded/D13-degraded.jpg"   # Track B: Immunization record
  "degraded/D14-degraded.jpg"   # Track B B4: Second lease
  "blurry/D01-blurry.jpg"       # Track A A6: Blurry notice (abstention test)
)

echo "Syncing test images to iPhone Photos..."
echo "Note: iPhone must be unlocked and trusted."
echo ""

SYNCED=0
FAILED=0

for img in "${DEMO_IMAGES[@]}"; do
  src="$SPIKE_DIR/$img"
  filename=$(basename "$img")
  
  if [ ! -f "$src" ]; then
    echo "  ⚠  Missing: $img"
    ((FAILED++))
    continue
  fi
  
  # Use osascript to import via Image Capture / Photos
  if osascript -e "
    tell application \"Image Capture\"
      -- This approach works for adding to Camera Roll via afc
    end tell
  " > /dev/null 2>&1; then
    echo "  ✓  $filename"
    ((SYNCED++))
  else
    # Fallback: use ifuse or direct afc copy if available
    echo "  →  $filename (manual copy needed — drag to Photos app)"
    ((FAILED++))
  fi
done

echo ""
echo "Synced: $SYNCED  |  Manual copy needed: $FAILED"
echo ""
echo "If auto-sync failed, drag these files manually to your iPhone:"
for img in "${DEMO_IMAGES[@]}"; do
  echo "  $SPIKE_DIR/$img"
done
```

**Document in `mobile/scripts/README.md`:**

```markdown
# CivicLens Dev Scripts

## Quick start

```bash
# First time setup
./scripts/serve_model.sh ~/models  # terminal 1 — keep running
./scripts/sync_test_assets.sh       # copies test images to iPhone Photos

# Every iteration
./scripts/dev_deploy.sh             # rebuild + reinstall

# Eval mode (for Monte Carlo experiments)
./scripts/dev_deploy.sh --eval      # starts inference server on :8080
```

## What each script does

| Script | Purpose | When to use |
|--------|---------|-------------|
| `dev_deploy.sh` | Build, install, summarize | Every code change |
| `serve_model.sh` | Serve Gemma model over HTTP | Keep running in background |
| `sync_test_assets.sh` | Copy spike images to iPhone Photos | Once per device |
| `build_llama_ios.sh` | Rebuild llama.cpp dylib (existing) | Only when llama.cpp changes |

## Iteration cycle

1. Make code change in VS Code / Cursor
2. Run `./scripts/dev_deploy.sh` (~30-60s for incremental builds)
3. App relaunches on iPhone automatically
4. Test using images already in Photos app
5. Repeat
```

---

### Part 2: Agent-Automated Static Analysis

Run these before the human walkthrough. Fix everything found here without human involvement.

**String audit — find all technical labels in user-visible code:**

```bash
# Run from mobile/ directory
# Find every user-visible string that contains technical model output labels
grep -rn \
  "likely_satisfies\|likely_does_not_satisfy\|insufficient_information\|hallucinated\|residency_ambiguous\|invalid_proof\|same_residency_category_duplicate\|confidence.*high\|evidence:" \
  lib/ \
  --include="*.dart" \
  | grep -v "_test.dart" \
  | grep -v "// " \
  > /tmp/technical_strings.txt

cat /tmp/technical_strings.txt
```

Replace every occurrence with the resident-friendly strings from this table. These replacements must happen in the display layer — not in the data model. The data model keeps the canonical labels; the UI translates them:

| Technical label | Resident-friendly display string |
|----------------|--------------------------------|
| `likely_satisfies` | "Appears to meet this requirement" |
| `likely_does_not_satisfy` | "May not meet this requirement" |
| `insufficient_information` | "Unclear — needs review" |
| `missing` (as status) | "Not found in your documents" |
| `questionable` | "Accepted by some offices — check with yours" |
| `residency_ambiguous` | "Acceptance varies by office" |
| `invalid_proof` | "This type of document is not accepted" |
| `same_residency_category_duplicate` | "Same type as another document you submitted" |
| confidence level display | Remove entirely from resident-facing screens |
| `evidence:` field | Remove from resident-facing screens (keep in debug/eval only) |

Create `mobile/lib/shared/utils/label_formatter.dart`:

```dart
class LabelFormatter {
  static String assessmentLabel(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'likely_satisfies':      return 'Appears to meet this requirement';
      case 'likely_does_not_satisfy': return 'May not meet this requirement';
      case 'insufficient_information': return 'Unclear — needs review';
      case 'missing':               return 'Not found in your documents';
      case 'questionable':          return 'Accepted by some offices — check with yours';
      case 'residency_ambiguous':   return 'Acceptance varies by office';
      case 'invalid_proof':         return 'This type of document is not accepted';
      case 'same_residency_category_duplicate':
        return 'Same type as another document you submitted';
      case 'satisfied':             return 'Looks good';
      default: return raw ?? 'Unknown';
    }
  }

  static String requirementLabel(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'proof_of_age':          return 'Proof of Age';
      case 'residency_proof_1':     return 'Residency Proof (1 of 2)';
      case 'residency_proof_2':     return 'Residency Proof (2 of 2)';
      case 'immunization_record':   return 'Immunization Record';
      case 'grade_indicator':       return 'Grade Indicator (if applicable)';
      case 'earned_income':         return 'Earned Income';
      case 'residency':             return 'Proof of Residency';
      case 'household_expenses':    return 'Household Expenses';
      default: return raw ?? 'Unknown';
    }
  }
  
  // Never show confidence level to residents
  // Use this if you need to gate on confidence internally
  static bool isHighConfidence(String? raw) => raw?.toLowerCase() == 'high';
}
```

**Flutter analyze:**

```bash
cd mobile && flutter analyze
```

Fix every error. Treat warnings that appear in user-facing code as errors this week.

**Widget tests for display states:**

Write widget tests for the key display states. These run in CI without a device and catch regressions:

```dart
// test/widget/track_a_results_test.dart
void main() {
  testWidgets('Track A results shows deadline prominently', (tester) async {
    final mockResult = TrackAResult(
      noticeSummary: NoticeSummary(
        requestedCategories: ['earned_income'],
        deadline: 'April 15, 2026',
        consequence: 'case_closure',
      ),
      proofPack: [
        ProofPackItem(
          category: 'earned_income',
          matchedDocument: 'D03',
          assessment: AssessmentLabel.likelySatisfies,
          confidence: ConfidenceLevel.high,
          evidence: '',
          caveats: '',
        ),
      ],
      actionSummary: 'Your pay stub appears to cover what DTA is asking for.',
    );
    
    await tester.pumpWidget(
      MaterialApp(home: TrackAResultsScreen(result: mockResult)),
    );
    
    // Deadline must be visible
    expect(find.text('April 15, 2026'), findsWidgets);
    
    // No technical labels visible
    expect(find.text('likely_satisfies'), findsNothing);
    expect(find.text('high'), findsNothing);
    
    // Action summary visible
    expect(find.textContaining('pay stub appears to cover'), findsOneWidget);
  });

  testWidgets('Track A results shows MISSING item in red', (tester) async {
    final mockResult = TrackAResult(
      noticeSummary: NoticeSummary(
        requestedCategories: ['earned_income'],
        deadline: 'April 15, 2026',
        consequence: 'case_closure',
      ),
      proofPack: [
        ProofPackItem(
          category: 'earned_income',
          matchedDocument: 'MISSING',
          assessment: AssessmentLabel.missing,
          confidence: ConfidenceLevel.low,
          evidence: '',
          caveats: '',
        ),
      ],
      actionSummary: "You're missing 1 required document.",
    );
    
    await tester.pumpWidget(
      MaterialApp(home: TrackAResultsScreen(result: mockResult)),
    );
    
    // MISSING must be displayed with resident-friendly label
    expect(find.text('Not found in your documents'), findsOneWidget);
    expect(find.text('MISSING'), findsNothing); // raw value should not appear
  });

  testWidgets('Track B duplicate category shows warning banner', (tester) async {
    final mockResult = TrackBResult(
      requirements: [...],
      duplicateCategoryFlag: true,
      duplicateCategoryExplanation: 'same_residency_category_duplicate',
      familySummary: 'You need a lease AND a different document type.',
    );
    
    await tester.pumpWidget(
      MaterialApp(home: TrackBResultsScreen(result: mockResult)),
    );
    
    // Warning banner must be visible
    expect(find.textContaining('two leases'), findsOneWidget);
    expect(find.textContaining('different'), findsOneWidget);
  });
}
```

Run with:
```bash
cd mobile && flutter test test/widget/
```

---

### Part 3: Human Walkthrough (your job — 60 minutes)

After Agent 1 has completed the static analysis fixes and the `dev_deploy.sh` script works, you do one device walkthrough. Use this checklist — check each item, note anything that looks wrong with a screenshot and brief description.

**Setup (5 min):**
```bash
./mobile/scripts/sync_test_assets.sh   # ensure test images in Photos
./mobile/scripts/dev_deploy.sh          # fresh install
```

**Walk these flows in order:**

```
FLOW 1: Track A — D01/D03 happy path (the RMV story)
[ ] Home screen looks polished, no placeholder text
[ ] Tap "SNAP Benefits" — navigates correctly
[ ] Upload D01-degraded.jpg as notice — blur check passes, slot fills
[ ] Upload D03-degraded.jpg as pay stub — slot fills
[ ] Tap "Analyze" — processing state visible, not frozen
[ ] Results: deadline banner is the FIRST thing I see
[ ] Results: "earned income" row shows green satisfied status
[ ] Results: no technical labels anywhere on screen
[ ] Action summary: reads like a knowledgeable friend, not a computer
[ ] Back/start over navigation works

FLOW 2: Track A — A3 stale pay stub
[ ] Upload D01-degraded.jpg as notice
[ ] Upload D04-degraded.jpg as stale pay stub
[ ] Results: income row shows "May not meet this requirement"
[ ] Caveats mention the date issue
[ ] Action summary tells me to get a more recent pay stub

FLOW 3: Track A — A6 blurry notice
[ ] Upload D01-blurry.jpg as notice
[ ] Upload D03-degraded.jpg as pay stub
[ ] Results: amber "unclear notice" banner visible
[ ] App does not confidently assert wrong deadline

FLOW 4: Track B — B1 complete packet
[ ] Tap "School Enrollment" from home
[ ] Upload D12, D05, D06, D13
[ ] Results: all 4 requirements green
[ ] No technical labels
[ ] Family summary is clear

FLOW 5: Track B — B4 duplicate leases
[ ] Upload D12, D05, D14, D13
[ ] Results: duplicate category warning banner is unmissable
[ ] Warning explains in plain language: two leases = one category
[ ] Family summary tells me what to replace

FLOW 6: Error states
[ ] Take a deliberately blurry photo — blur warning appears
[ ] "Use anyway" override works
[ ] Try navigating back mid-inference — app handles gracefully
```

**Document findings in `docs/sprint/week3_human_qa.md`:**
```markdown
# Week 3 Human QA Findings
Date: [date]
Device: iPhone [model], iOS [version]

## P0 Issues (blocking demo recording)
- [issue description + screenshot filename]

## P1 Issues (visible to judges)
- [issue description + screenshot filename]

## P2 Issues (edge cases)
- [issue description]

## Looks Good
- [things that passed]
```

Hand this document to Agent 1 and they fix everything P0 and P1.

---

### Part 4: Track A Demo Flow Polish

After the human walkthrough findings are fixed, these specific improvements should be verified:

**Deadline prominence:** The deadline banner must be the first element after the screen title. Style:

```dart
// In track_a_results_screen.dart — deadline banner at top
if (result.noticeSummary.deadline.isNotEmpty &&
    result.noticeSummary.deadline != 'UNCERTAIN')
  Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF3F3),
      border: Border.all(color: const Color(0xFFB71C1C), width: 2),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Respond by ${result.noticeSummary.deadline}',
          style: const TextStyle(
            fontSize: 18, fontWeight: FontWeight.bold,
            color: Color(0xFFB71C1C),
          ),
        ),
        if (result.noticeSummary.consequence.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _formatConsequence(result.noticeSummary.consequence),
              style: const TextStyle(fontSize: 14, color: Color(0xFF555555)),
            ),
          ),
      ],
    ),
  ),
```

**Action summary prominence:** Action summary should be styled as a card with slightly larger font than the proof pack rows — it's the most important thing a resident reads.

**MISSING item treatment:** Red background, explicit language from `LabelFormatter`.

**Uncertain notice (A6):** Amber banner with DTA contact info when deadline = "UNCERTAIN".

---

### Part 5: Track B B4 Polish

Duplicate category warning banner — must be unmissable:

```dart
if (result.duplicateCategoryFlag)
  Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFBEB),
      border: Border.all(color: const Color(0xFFB45309), width: 2),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Two documents from the same category',
          style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.bold,
            color: Color(0xFF92400E),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'You submitted two leases. BPS requires documents from two '
          'different categories — for example, a lease AND a utility bill. '
          'A second lease does not count as a second proof.',
          style: TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
        ),
      ],
    ),
  ),
```

---

### Acceptance Criteria

- [ ] `dev_deploy.sh` builds and installs on iPhone in one command
- [ ] `serve_model.sh` serves the model file with a `/health` endpoint
- [ ] `sync_test_assets.sh` documented even if full auto-sync not possible
- [ ] All technical labels removed from user-visible code (grep returns 0 results)
- [ ] `LabelFormatter` class in place and used by all results screens
- [ ] Widget tests pass for Track A results, MISSING item, Track B duplicate flag
- [ ] Human walkthrough completed, all P0 and P1 findings resolved
- [ ] Deadline banner is first element in Track A results
- [ ] Duplicate category banner is unmissable in Track B B4
- [ ] Action summary styled prominently on both results screens
- [ ] `flutter analyze` returns 0 errors

---

---

## Agent 2 — Eval Server + Monte Carlo Harness

**Owns:** `mobile/lib/eval/`, `research/eval/`, `mobile/scripts/`

**Primary goal:** Build the infrastructure for systematic performance measurement on device. By Friday: the Mac can drive 50+ automated inference runs on the iPhone without human intervention, results scored against ground truth, metrics computed.

**Why this matters:** The research papers need empirically measured performance on E2B on-device — not E4B via Ollama, which is what the original spike measured. The Monte Carlo harness gives you statistical validity. The visual token budget ablation gives you a clean experiment with a meaningful finding.

---

### Part 1: Eval Server (Flutter app, debug mode only)

Add a debug eval server to the Flutter app. This server runs only when the app is launched with `--dart-define=EVAL_MODE=true`. It exposes an HTTP endpoint on port 8080 that accepts inference requests from the Mac.

**Add to `pubspec.yaml`:**
```yaml
shelf: ^1.4.1
shelf_router: ^1.1.4
```

**Create `mobile/lib/eval/eval_server.dart`:**

```dart
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

class EvalServer {
  final InferenceService _inferenceService;
  HttpServer? _server;
  
  EvalServer(this._inferenceService);
  
  Future<void> start({int port = 8080}) async {
    final router = Router();
    
    // Health check
    router.get('/health', (Request req) {
      return Response.ok(jsonEncode({
        'status': 'ok',
        'model': 'gemma4-e2b',
        'timestamp': DateTime.now().toIso8601String(),
      }), headers: {'content-type': 'application/json'});
    });
    
    // Single inference request
    router.post('/infer', (Request req) async {
      final body = jsonDecode(await req.readAsString());
      
      final imageB64 = body['image'] as String;
      final prompt = body['prompt'] as String;
      final track = body['track'] as String; // 'a' or 'b'
      final temperature = (body['temperature'] as num?)?.toDouble() ?? 0.0;
      final tokenBudget = (body['token_budget'] as num?)?.toInt(); // null = default
      
      final imageBytes = base64Decode(imageB64);
      
      final stopwatch = Stopwatch()..start();
      
      String? rawResponse;
      try {
        rawResponse = await _inferenceService.inferRaw(
          imageBytes: imageBytes,
          prompt: prompt,
          temperature: temperature,
          tokenBudget: tokenBudget,
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'content-type': 'application/json'},
        );
      }
      
      stopwatch.stop();
      
      return Response.ok(
        jsonEncode({
          'response': rawResponse,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
          'parse_ok': rawResponse != null && rawResponse.isNotEmpty,
        }),
        headers: {'content-type': 'application/json'},
      );
    });
    
    // Device info endpoint
    router.get('/device', (Request req) async {
      return Response.ok(jsonEncode({
        'platform': Platform.operatingSystem,
        'os_version': Platform.operatingSystemVersion,
        'processors': Platform.numberOfProcessors,
      }), headers: {'content-type': 'application/json'});
    });
    
    final handler = Pipeline()
        .addMiddleware(logRequests())
        .addHandler(router);
    
    _server = await shelf_io.serve(handler, '0.0.0.0', port);
    debugPrint('Eval server running on port $port');
  }
  
  Future<void> stop() async {
    await _server?.close(force: true);
  }
}
```

**Wire into `main.dart`:**
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  const evalMode = bool.fromEnvironment('EVAL_MODE', defaultValue: false);
  
  if (evalMode) {
    final inferenceService = InferenceService();
    await inferenceService.initialize();
    final evalServer = EvalServer(inferenceService);
    await evalServer.start();
    debugPrint('Running in eval mode — server on :8080');
  }
  
  runApp(const CivicLensApp());
}
```

**Launch command for eval mode:**
```bash
flutter run --dart-define=EVAL_MODE=true -d <device-id>
```

---

### Part 2: InferenceService raw inference method

Add `inferRaw()` to `inference_service.dart` that exposes temperature and token budget controls needed for the eval harness:

```dart
Future<String?> inferRaw({
  required Uint8List imageBytes,
  required String prompt,
  double temperature = 0.0,
  int? tokenBudget,  // null = model default; supports 70,140,280,560,1120
}) async {
  // Build the request with optional token budget
  // Token budget maps to Gemma 4's visual token budget parameter
  // Higher budget = better OCR/document parsing, higher latency
  final response = await _llamaClient.chatWithImages(
    prompt: prompt,
    images: [imageBytes],
    temperature: temperature,
    maxTokens: 2048,
    visualTokenBudget: tokenBudget,
  );
  return response.rawText;
}
```

---

### Part 3: Mac-side experiment runner

Create `research/eval/` directory with the full Python harness:

**`research/eval/runner.py`:**

```python
"""
CivicLens Monte Carlo Evaluation Runner

Drives systematic inference experiments against the on-device eval server.
Measures accuracy, hallucination rate, latency, and stability across N runs.

Usage:
  # Set phone IP first
  export PHONE_IP=192.168.1.X
  
  # Run D01+D03 Track A experiment, 20 runs, temperature 0
  python runner.py --artifacts D01,D03 --track a --runs 20 --temp 0.0
  
  # Visual token budget ablation on D03
  python runner.py --artifacts D03 --track a --runs 10 \
    --token-budgets 70,140,280,560,1120 --ablation
  
  # Full Monte Carlo (all demo artifacts, both temperatures)
  python runner.py --artifacts D01,D03,D04,D07,D10 \
    --track a --runs 20 --temp 0.0 --temp 0.3
"""

import argparse
import base64
import csv
import json
import os
import time
from collections import defaultdict
from pathlib import Path
import requests

# ── Config ────────────────────────────────────────────────────────────────────
PHONE_IP = os.environ.get('PHONE_IP', '192.168.1.1')
PHONE_URL = f"http://{PHONE_IP}:8080"
SPIKE_DIR = Path(__file__).parent.parent.parent / 'spike'
ARTIFACTS_CLEAN = SPIKE_DIR / 'artifacts' / 'clean'
ARTIFACTS_DEGRADED = SPIKE_DIR / 'artifacts' / 'degraded'
GROUND_TRUTH = SPIKE_DIR / 'artifacts' / 'clean' / 'html' / 'ground_truth.csv'
RESULTS_DIR = Path(__file__).parent / 'results'
RESULTS_DIR.mkdir(exist_ok=True)

# ── Ground truth loader ───────────────────────────────────────────────────────
def load_ground_truth() -> dict[str, dict[str, str]]:
    gt = defaultdict(dict)
    with open(GROUND_TRUTH) as f:
        for row in csv.DictReader(f):
            gt[row['artifact_id']][row['field_name']] = row['expected_value']
    return dict(gt)

# ── Image loader ──────────────────────────────────────────────────────────────
def load_image_b64(artifact_id: str, variant: str) -> str:
    if variant == 'clean':
        path = ARTIFACTS_CLEAN / f"{artifact_id}-clean.pdf"
        if not path.exists():
            # Try jpg
            path = ARTIFACTS_CLEAN / f"{artifact_id}-clean.jpg"
    else:
        path = ARTIFACTS_DEGRADED / f"{artifact_id}-{variant}.jpg"
    
    if not path.exists():
        raise FileNotFoundError(f"Artifact not found: {path}")
    
    with open(path, 'rb') as f:
        return base64.b64encode(f.read()).decode()

# ── Prompt builder ────────────────────────────────────────────────────────────
def build_prompt(artifact_id: str, gt: dict, track: str) -> str:
    fields = gt.get(artifact_id, {})
    # Build the extraction prompt with exactly the ground truth fields
    field_json = '\n'.join([f'  "{k}": "",' for k in fields.keys()])
    return f"""You are a document analysis assistant. Read the document carefully.

Rules:
- Extract only values clearly present in the document
- Read each field directly from its labeled location
- For pay-stub income: use current-period column only, not YTD
- Copy names character-by-character as printed
- If you cannot read a field, set its value to UNREADABLE
- Return ONLY valid JSON with exactly these keys. No markdown.

{{{field_json}
}}"""

# ── Scoring ───────────────────────────────────────────────────────────────────
def normalize(v: str) -> str:
    return v.lower().strip().replace(',', '').replace('$', '').replace(' ', '')

def score_field(extracted, expected: str) -> dict:
    if extracted is None or (isinstance(extracted, str) and not extracted.strip()):
        return {'score': 0, 'label': 'missing'}
    ext_n = normalize(str(extracted))
    exp_n = normalize(expected)
    if ext_n == 'unreadable':
        return {'score': 0, 'label': 'unreadable'}
    if ext_n == exp_n:
        return {'score': 2, 'label': 'exact'}
    if exp_n in ext_n or ext_n in exp_n:
        return {'score': 1, 'label': 'partial'}
    return {'score': -1, 'label': 'hallucinated'}

def parse_with_retry(raw: str) -> dict | None:
    if not raw or not raw.strip():
        return None
    cleaned = raw.strip()
    # Try direct parse
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        pass
    # Try wrapping bare output
    try:
        return json.loads('{' + cleaned + '}')
    except json.JSONDecodeError:
        pass
    # Try stripping markdown fences
    if '```' in cleaned:
        lines = cleaned.split('\n')
        inner = '\n'.join(l for l in lines if not l.startswith('```'))
        try:
            return json.loads(inner)
        except json.JSONDecodeError:
            pass
    return None

# ── Single inference call ─────────────────────────────────────────────────────
def run_inference(
    image_b64: str,
    prompt: str,
    track: str,
    temperature: float = 0.0,
    token_budget: int | None = None,
    timeout: int = 120,
) -> dict:
    payload = {
        'image': image_b64,
        'prompt': prompt,
        'track': track,
        'temperature': temperature,
    }
    if token_budget is not None:
        payload['token_budget'] = token_budget
    
    t0 = time.time()
    try:
        r = requests.post(f"{PHONE_URL}/infer", json=payload, timeout=timeout)
        r.raise_for_status()
        data = r.json()
        return {
            'response': data.get('response', ''),
            'elapsed_ms': data.get('elapsed_ms', int((time.time() - t0) * 1000)),
            'parse_ok': bool(data.get('response', '').strip()),
            'error': None,
        }
    except requests.exceptions.Timeout:
        return {'response': '', 'elapsed_ms': timeout * 1000, 'parse_ok': False, 'error': 'timeout'}
    except Exception as e:
        return {'response': '', 'elapsed_ms': 0, 'parse_ok': False, 'error': str(e)}

# ── Experiment runner ─────────────────────────────────────────────────────────
def run_experiment(
    artifact_id: str,
    variant: str,
    track: str,
    n_runs: int,
    temperature: float,
    token_budget: int | None,
    gt: dict,
    cooldown_s: float = 2.0,
) -> list[dict]:
    image_b64 = load_image_b64(artifact_id, variant)
    prompt = build_prompt(artifact_id, gt, track)
    fields = gt.get(artifact_id, {})
    
    results = []
    for i in range(n_runs):
        print(f"  {artifact_id} {variant} temp={temperature} budget={token_budget} "
              f"run {i+1}/{n_runs}", end='\r', flush=True)
        
        infer_result = run_inference(image_b64, prompt, track, temperature, token_budget)
        parsed = parse_with_retry(infer_result['response'])
        
        # Score against ground truth
        field_scores = {}
        if parsed and fields:
            for fname, expected in fields.items():
                field_scores[fname] = score_field(parsed.get(fname), expected)
        
        pts = [s['score'] for s in field_scores.values()]
        avg_score = sum(pts) / len(pts) if pts else None
        halluc_count = sum(1 for s in field_scores.values() if s['label'] == 'hallucinated')
        
        record = {
            'artifact_id': artifact_id,
            'variant': variant,
            'track': track,
            'run': i,
            'temperature': temperature,
            'token_budget': token_budget,
            'elapsed_ms': infer_result['elapsed_ms'],
            'parse_ok': parsed is not None,
            'error': infer_result['error'],
            'raw_response': infer_result['response'],
            'field_scores': field_scores,
            'avg_score': round(avg_score, 4) if avg_score is not None else None,
            'hallucination_count': halluc_count,
        }
        results.append(record)
        
        # Thermal cooldown between runs
        if i < n_runs - 1:
            time.sleep(cooldown_s)
    
    print()  # newline after progress line
    return results

# ── Summary stats ─────────────────────────────────────────────────────────────
def compute_summary(results: list[dict]) -> dict:
    scored = [r for r in results if r['avg_score'] is not None]
    if not scored:
        return {}
    
    scores = [r['avg_score'] for r in scored]
    latencies = [r['elapsed_ms'] for r in results if r['elapsed_ms']]
    all_labels = [
        s['label']
        for r in scored
        for s in r['field_scores'].values()
    ]
    
    n_fields = len(all_labels)
    
    return {
        'n_runs': len(results),
        'n_scored': len(scored),
        'parse_ok_rate': sum(1 for r in results if r['parse_ok']) / len(results),
        'avg_score_mean': sum(scores) / len(scores),
        'avg_score_std': (sum((s - sum(scores)/len(scores))**2 for s in scores) / len(scores)) ** 0.5,
        'hallucination_rate': all_labels.count('hallucinated') / n_fields if n_fields else 0,
        'exact_rate': all_labels.count('exact') / n_fields if n_fields else 0,
        'missing_rate': all_labels.count('missing') / n_fields if n_fields else 0,
        'unreadable_rate': all_labels.count('unreadable') / n_fields if n_fields else 0,
        'latency_mean_ms': sum(latencies) / len(latencies) if latencies else 0,
        'latency_p95_ms': sorted(latencies)[int(len(latencies) * 0.95)] if latencies else 0,
        'latency_std_ms': (sum((l - sum(latencies)/len(latencies))**2 for l in latencies) / len(latencies)) ** 0.5 if latencies else 0,
    }

# ── Main ──────────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--artifacts', default='D01,D03')
    parser.add_argument('--track', default='a')
    parser.add_argument('--variants', default='clean,degraded')
    parser.add_argument('--runs', type=int, default=20)
    parser.add_argument('--temp', type=float, action='append', default=[])
    parser.add_argument('--token-budgets', default='')
    parser.add_argument('--ablation', action='store_true')
    parser.add_argument('--cooldown', type=float, default=2.0)
    parser.add_argument('--out', default='')
    args = parser.parse_args()
    
    # Defaults
    temperatures = args.temp if args.temp else [0.0]
    artifacts = [a.strip() for a in args.artifacts.split(',')]
    variants = [v.strip() for v in args.variants.split(',')]
    token_budgets = (
        [int(b) for b in args.token_budgets.split(',') if b.strip()]
        if args.token_budgets else [None]
    )
    
    gt = load_ground_truth()
    
    # Health check
    try:
        r = requests.get(f"{PHONE_URL}/health", timeout=5)
        print(f"Phone connected: {r.json()}")
    except Exception as e:
        print(f"ERROR: Cannot reach phone at {PHONE_URL}: {e}")
        print("Make sure the app is running in eval mode and you're on the same WiFi")
        return
    
    # Run experiments
    all_results = []
    experiment_id = f"exp_{int(time.time())}"
    
    for artifact in artifacts:
        for variant in variants:
            for temp in temperatures:
                for budget in token_budgets:
                    print(f"\nRunning: {artifact} {variant} temp={temp} budget={budget}")
                    results = run_experiment(
                        artifact, variant, args.track,
                        args.runs, temp, budget, gt,
                        cooldown_s=args.cooldown,
                    )
                    summary = compute_summary(results)
                    
                    print(f"  avg_score: {summary.get('avg_score_mean', 0):.3f} "
                          f"± {summary.get('avg_score_std', 0):.3f}")
                    print(f"  hallucination_rate: {summary.get('hallucination_rate', 0):.1%}")
                    print(f"  latency_mean: {summary.get('latency_mean_ms', 0):.0f}ms "
                          f"p95: {summary.get('latency_p95_ms', 0):.0f}ms")
                    
                    all_results.extend(results)
    
    # Save results
    out_path = args.out or RESULTS_DIR / f"{experiment_id}.jsonl"
    with open(out_path, 'w') as f:
        for r in all_results:
            f.write(json.dumps(r, ensure_ascii=False) + '\n')
    
    print(f"\nResults saved to {out_path}")
    print(f"Total runs: {len(all_results)}")

if __name__ == '__main__':
    main()
```

---

### Part 4: Visual Token Budget Ablation

This is a self-contained experiment that produces one of the cleanest figures for the NLP/AI paper. Run it once the eval server is confirmed working.

```bash
# Token budget ablation on D03 (pay stub) — most interesting for document parsing
python research/eval/runner.py \
  --artifacts D03 \
  --track a \
  --variants clean,degraded \
  --runs 10 \
  --temp 0.0 \
  --token-budgets 70,140,280,560,1120 \
  --cooldown 3.0 \
  --out research/eval/results/token_budget_ablation.jsonl
```

Expected finding: accuracy improves with higher token budgets on document-dense artifacts (D01 notice, D03 pay stub), with diminishing returns above 560. Latency increases roughly linearly. This tradeoff curve belongs in both papers.

---

### Part 5: Thermal characterization

Add a temperature logging endpoint to the eval server (iOS doesn't expose CPU temp directly, but you can use proxy metrics):

```dart
router.get('/metrics', (Request req) async {
  return Response.ok(jsonEncode({
    'timestamp': DateTime.now().toIso8601String(),
    'memory_used_mb': ProcessInfo.currentRss ~/ (1024 * 1024),
    // Inference count since server start — use to detect throttling
    'inference_count': _inferenceCount,
    'last_inference_ms': _lastInferenceMs,
  }), headers: {'content-type': 'application/json'});
});
```

Poll `/metrics` every 30 seconds during long experiments and log to a separate CSV. Plot inference latency vs inference count — the curve shape tells you whether thermal throttling is affecting results.

---

### Acceptance Criteria

- [ ] Eval server starts when app launched with `EVAL_MODE=true`
- [ ] `/health` endpoint reachable from Mac on same WiFi
- [ ] `/infer` endpoint handles single image + prompt, returns response + timing
- [ ] Mac-side runner connects, sends a test request, gets a valid response
- [ ] 20-run D01/D03 experiment completes unattended, results saved to JSONL
- [ ] Token budget ablation script runs and produces results
- [ ] Results include all required fields for scoring (field_scores, avg_score, hallucination_count)

---

---

## Agent 3 — Web Demo Parity + Research Repository Foundation

**Owns:** `web_demo/`, `docs/`, `README.md`, `ARCHITECTURE.md`, `spike/` organization

**Primary goal:** Two deliverables this week. First, bring the HF Spaces web demo to full feature parity with the mobile app. Second, build the repository foundation that will support both the Kaggle writeup and the two research papers.

---

### Part 1: Web Demo Feature Parity

The web demo at `https://DanFinkel-civiclens.hf.space` needs to match what the mobile app now does.

**Track A additions:**
- Notice upload as first input (currently Track A may treat all docs equally)
- Deadline banner prominent in results
- MISSING items visually distinct
- Resident-friendly language (no technical labels — same string replacement table as Agent 1)
- A6 uncertain notice handling: amber warning when notice fields return UNCERTAIN

**Track B additions:**
- Duplicate category warning banner
- Phone bill questionable treatment
- Family summary prominent

**Shared:**
- Blur detection pre-processing on all uploaded images
- Confidence color coding: green/amber/red for satisfied/questionable/missing
- Action summary as the primary output, styled prominently
- Loading state: "Reading your documents... Analyzing requirements..."

**HF Spaces reliability:**
- Add a `/health` endpoint that returns 200
- Set up a keep-warm ping (GitHub Actions scheduled workflow hitting `/health` every 30 minutes during business hours)
- Test cold start time and document it — if >90 seconds, add a loading message

---

### Part 2: Repository Structure

The repo needs to tell the story of the project from spike through build. Organize it so a reader who clones it understands not just what was built but why.

**Final repo structure:**
```
civiclens/
├── README.md                    # Project overview, demo link, video link, setup
├── ARCHITECTURE.md              # Technical decisions and rationale
├── RESEARCH.md                  # Links to papers, methodology, findings
├── mobile/                      # Flutter app (existing)
├── web_demo/                    # Gradio web demo (existing)
├── research/
│   ├── eval/                    # Monte Carlo harness (Agent 2)
│   │   ├── runner.py
│   │   ├── results/             # JSONL experiment results (gitignored if large)
│   │   └── README.md
│   └── papers/
│       ├── nlp_ai/
│       │   └── outline.md       # Paper 1 outline
│       └── civic_tech/
│           └── outline.md       # Paper 2 outline
└── spike/                       # Feasibility spike (existing)
    ├── README.md                # Spike methodology and findings summary
    ├── artifacts/               # 16 synthetic documents
    ├── scripts/                 # Experiment runners
    └── docs/                    # Findings reports
        ├── warmup_readout.docx
        ├── day1_findings.docx
        ├── day2_findings.md
        ├── day3_findings.md
        └── day5_decision_memo.md
```

---

### Part 3: README.md (final version)

Write the production README. Every section should be complete enough to stand alone.

```markdown
# CivicLens

Privacy-first civic document intelligence using on-device Gemma 4.

CivicLens helps residents prepare documents for government benefit processes 
and school enrollment. Upload your documents. The app checks them against 
official requirements entirely on your device — nothing is sent to a server.

## Demo

[Live demo](https://DanFinkel-civiclens.hf.space) | [Video](https://youtube.com/...) | [Paper (coming soon)]

## What It Does

**SNAP Benefits (Track A):** Photograph your DTA notice and supporting documents. 
CivicLens reads the notice, identifies what proof categories are required and 
the deadline, and tells you whether your documents cover each requirement.

**School Enrollment (Track B):** Photograph your BPS registration documents. 
CivicLens checks all four requirements, flags the two-category residency rule 
if violated, and tells you what to bring and what to replace.

## Privacy Architecture

All inference runs on-device using Gemma 4 E2B via llama.cpp with Metal GPU 
acceleration. Documents never leave the phone. Network is used only for the 
one-time 2.9GB model download.

[Architecture diagram]

## Performance (iPhone 16, Gemma 4 E2B)

| Metric | Result |
|--------|--------|
| OCR (4 documents) | 391ms |
| LLM inference | 11.9s |
| Total pipeline | 15.3s |
| Model size (Q4_K_M) | 2.9GB |

## Technical Foundation

CivicLens was built on a five-day feasibility spike that tested Gemma 4 E4B 
against 16 synthetic civic documents before writing any product code. Key findings:

- Document classification: 100% accuracy on degraded phone photos
- Category mapping: 85.9% accuracy (BPS), 66.7% (SNAP)  
- Critical safety checks: zero false positives across all test scenarios
- Identified failure modes informed architectural decisions

See [spike/README.md](spike/README.md) for full methodology and findings.

## Setup

[Local development instructions]
[Model download instructions]
[Eval server instructions]

## Known Limitations

- Field-level extraction: ~40% hallucination rate on complex tabular layouts
  (pay stubs with adjacent current/YTD columns). Mitigated by human review UX.
- Image quality: model cannot self-report illegibility. Mitigated by blur 
  detection pre-processing.
- Missing-item detection: 50-67% recall. Mitigated by action summary guidance.

## Research

[Links to papers when published]

## License

Apache 2.0
```

---

### Part 4: Paper Outlines

Create the two paper outlines. These are living documents — skeletal now, filled in as the Monte Carlo results come in.

**`research/papers/nlp_ai/outline.md`:**

```markdown
# On-Device Multimodal LLM Performance for Civic Document Understanding

## Target venue
[TBD — CHI, EMNLP, or ACL findings track]

## Abstract (draft)
We present a systematic evaluation of Gemma 4 E2B for civic document 
understanding on consumer mobile hardware. Using a structured feasibility 
spike methodology with 16 synthetic civic documents and formal ground truth, 
we measure field extraction accuracy, hallucination rates, and classification 
performance on degraded phone photographs — the realistic input quality for 
the target population. We identify three systematic failure modes (column 
confusion on tabular layouts, name confabulation, date misattribution), 
characterize their prevalence and severity, and evaluate prompt-engineering 
mitigations. We report the accuracy-latency tradeoff across Gemma 4's 
configurable visual token budget settings on a physical iPhone 16, providing 
the first published measurements of this parameter on civic document tasks.

## Sections
1. Introduction — the civic document burden, gap in prior work
2. Related work — document AI, on-device LLM, civic tech
3. Methodology — spike framework, synthetic artifacts, scoring rubric
4. Experiment 1 — E4B baseline (original spike, Days 1-3)
5. Experiment 2 — E2B on-device (Monte Carlo, this work)
6. Experiment 3 — Visual token budget ablation
7. Failure mode analysis — column confusion, name confabulation, date misattribution
8. Discussion — implications for deployment, prompt mitigations
9. Limitations and future work

## Key figures needed
- Accuracy by document type (clean vs degraded) — heatmap
- Hallucination rate by field type — bar chart
- Token budget vs accuracy vs latency — line chart (ablation)
- Latency distribution across runs (thermal effects) — box plot
- Confusion matrix for classification task
```

**`research/papers/civic_tech/outline.md`:**

```markdown
# Privacy-First Document Intelligence for Government Service Navigation

## Target venue
CSCW, CHI, or Government Information Quarterly

## Abstract (draft)
Administrative burden — the time and cognitive load required to navigate 
government benefit systems — disproportionately affects low-income residents. 
We describe CivicLens, a privacy-first mobile application that uses on-device 
Gemma 4 to help residents verify document packets before submitting to 
government agencies. We report on the design process, which used a structured 
feasibility spike to empirically characterize model capabilities before product 
decisions, and on the architectural choices made in response to specific failure 
modes. We argue that on-device inference is not merely a technical preference 
but a design requirement for applications handling sensitive civic documents, 
and we describe how known model limitations were addressed through UX design 
rather than model improvement.

## Sections
1. Introduction — administrative burden, the "knowledgeable friend" gap
2. Related work — civic tech, benefits navigation tools, document AI
3. Problem framing — SNAP recertification, BPS enrollment as case studies
4. Methodology — evidence-driven design via feasibility spike
5. System description — CivicLens architecture, Track A, Track B
6. Failure modes as design constraints — how limitations shaped UX decisions
7. Privacy as a requirement — on-device inference rationale
8. Evaluation — accuracy on demo scenarios, resident-facing metrics
9. Limitations — what CivicLens doesn't do (submission, caseworker side)
10. Future work — fine-tuning, expansion to other document types

## Key arguments
- Failure modes are design constraints, not blockers
- Blur detection is a safety requirement, not a feature
- Human-in-loop is a civic design principle, not a technical fallback
- Synthetic test artifacts with ground truth as a methodology contribution
```

---

### Acceptance Criteria

- [ ] Web demo feature parity with mobile (Track A deadline banner, Track B duplicate warning, no technical labels)
- [ ] HF Spaces keep-warm ping working
- [ ] README.md complete and accurate
- [ ] ARCHITECTURE.md explains all major technical decisions
- [ ] `spike/README.md` explains the spike methodology and links to findings
- [ ] Both paper outlines committed to `research/papers/`
- [ ] Repo structure matches the plan above

---

---

## Agent 4 — Video Script, Demo Recording, Kaggle Writeup Draft

**Owns:** Video, `docs/video/`, `docs/kaggle_writeup_draft.md`

**Primary goal:** Recorded video uploaded to YouTube by Friday. Kaggle writeup draft complete enough that week 4 is editing, not writing.

---

### Part 1: Final Video Script

The video must be under 3 minutes. Every second is allocated.

**0:00–0:25 — The problem (no product shown)**

Voiceover only, or simple text on screen.

> "A few years ago I drove to the RMV to upgrade my license to a Real ID. I brought what I thought were the right documents. I was turned away because my W-2 didn't have my Social Security number on it. I drove home, found the right document, drove back. The requirement existed — it just wasn't communicated clearly, and I had no way to check my specific documents against it before I went."

> "That same problem plays out every day for families navigating SNAP recertification, school enrollment, housing applications. The documents they need exist. The requirements are published. The gap is knowing whether what you have is what is needed — before you show up somewhere and find out it isn't."

**0:25–0:40 — The approach (spike methodology, brief)**

Show: a few seconds of the spike results tables or architecture diagram.

> "Before building anything, we spent a week rigorously testing whether Gemma 4 could reliably handle real civic documents — government notices, pay stubs, leases, birth certificates, photographed on a phone. We measured accuracy, failure modes, and what the model genuinely cannot do. Those findings shaped every decision in what we built."

**0:40–1:45 — Demo: Track A (SNAP income verification)**

Show: screen recording on real iPhone.

Scene 1 (~20s): Home screen → select "SNAP Benefits"

Scene 2 (~15s): Photograph the D01 notice. Blur check passes. Notice slot filled.

Scene 3 (~15s): Photograph the D03 pay stub. Slot filled.

Scene 4 (~5s): Tap "Analyze My Documents"

Scene 5 (~10s): Processing state — "Reading your notice... Analyzing your documents..."

Scene 6 (~20s): Results. Deadline banner: "Respond by April 15." Proof pack: earned income — D03 satisfies it. Action summary: plain language guidance.

Voiceover during Scene 6: "The app reads the notice, identifies the deadline, checks the pay stub against the requirement, and tells the resident what to do — in plain language, in 15 seconds, without their documents ever leaving the phone."

**1:45–2:20 — Demo: Track B (BPS duplicate category)**

Show: screen recording continuing.

Scene 7 (~15s): Switch to "School Enrollment." Upload D12 (birth certificate), D05 (lease 1), D14 (lease 2 — same address), D13 (immunization record).

Scene 8 (~20s): Results. Three requirements satisfied. Duplicate warning banner: "Two leases from the same address count as one proof. You need a lease AND a different type of document, like a utility bill."

Voiceover: "This is the kind of thing a caseworker would catch at the enrollment office — after the family has already made the trip. CivicLens catches it at home."

**2:20–2:45 — Privacy architecture**

Show: architecture diagram (from Agent 3's ARCHITECTURE.md).

> "Every document is processed entirely on the device using Gemma 4 E2B. OCR runs locally. Inference runs locally. Nothing is uploaded. For a resident submitting a birth certificate and a state ID, that matters."

**2:45–3:00 — Close**

Show: app on phone, then repo/demo URL.

> "CivicLens. The knowledgeable friend who checks your documents before you go."

> "Open source. On device. Built on Gemma 4."

---

### Part 2: Recording Setup

**Equipment:**
- iPhone 16 (the demo device) with screen recording enabled
- Mac with QuickTime for capture if needed
- Good lighting — the document photos need to look realistic, not staged

**Recording order:**
1. Record Track A D01/D03 flow 3 times — pick the cleanest take
2. Record Track B B4 flow 3 times — pick the cleanest take
3. Record architecture diagram screen share (30 seconds)
4. Record the close screen (5 seconds)

**Before recording:**
- Clear the app state (fresh install or clear data)
- Download the model to avoid showing download screen in video
- Set phone to Do Not Disturb
- Turn off battery percentage display if low
- Have D01-degraded.jpg, D03-degraded.jpg, D12-degraded.jpg, D05-degraded.jpg, D14-degraded.jpg, D13-degraded.jpg in Photos app ready to select

**Editing:**
- Use iMovie, DaVinci Resolve, or CapCut
- Add voiceover audio to the silent screen recording sections
- Add the RMV story as text on screen for the opening 25 seconds
- Final cut must be ≤ 3:00 — aim for 2:55 to give margin
- Export at 1080p minimum
- Upload to YouTube as Unlisted first, share for review, then make Public for submission

---

### Part 3: Kaggle Writeup Draft

Target: 1,400 words (under 1,500 limit with some room). Write the full draft this week. Week 4 is editing and polishing.

**Structure with word budgets:**

```markdown
# CivicLens: Privacy-First Civic Document Intelligence with On-Device Gemma 4

## Subtitle
Helping residents navigate SNAP benefits and school enrollment using 
local multimodal AI — no documents leave the device.

## 1. The Problem (150 words)
Administrative burden in government service delivery. The document gap.
The RMV story. Two concrete use cases: SNAP recertification, BPS enrollment.
The "knowledgeable friend" framing.

## 2. Why On-Device Gemma 4 (150 words)
Privacy requirement for sensitive civic documents. Gemma 4 E2B on consumer
hardware. Multimodal capability for phone photos. The specific intersection
of model capability and use case requirement. Apache 2.0 — deployable
without licensing constraints.

## 3. Evidence-Driven Development: The Feasibility Spike (350 words)
This is the differentiator. Five-day structured spike before any product code.
16 synthetic documents. 100+ inference experiments. Formal pass/fail thresholds.
Key findings: what works (classification 100%, mapping 85.9%), what doesn't
(field extraction hallucination rate, abstention on blurry images).
How failure modes became design constraints.
The scorer bug — intellectual honesty moment.
Decision tree → proceed to build with known constraints.

## 4. Architecture (250 words)
On-device pipeline diagram. OCR (391ms) → LLM (11.9s) → JSON (15.3s total).
Flutter + llama.cpp + Metal GPU. The FFI struct debugging story (brief).
Blur detection pre-processing rationale (from spike A6 finding).
JSON retry wrapper (from spike E4B finding).
Human-in-loop design principle. Never auto-approve.
HF Spaces web demo as accessible fallback.

## 5. Results and Known Limitations (250 words)
What works in production: classification, mapping, JSON reliability, latency.
What the spike found and how the product addresses it:
- Field extraction hallucination → human review UX
- Blurry image abstention failure → blur detection gate
- Missing-item detection → action summary as primary output
Honest about limitations — this is intentional.

## 6. Impact and Next Steps (150 words)
The resident story. Privacy as equity. On-device as a requirement not a feature.
Research direction: two papers in progress (NLP/AI, civic tech).
Monte Carlo evaluation infrastructure for rigorous measurement.
Post-hackathon development path.
```

---

### Acceptance Criteria

- [ ] Video recorded, edited to ≤3:00, uploaded to YouTube (unlisted for review)
- [ ] Both Track A (D01/D03) and Track B (B4) scenarios captured cleanly
- [ ] RMV story in the opening 25 seconds
- [ ] Privacy architecture diagram visible in video
- [ ] Kaggle writeup draft complete at ~1,400 words
- [ ] Writeup covers all 6 sections with correct word budgets
- [ ] Cover image created for Kaggle submission (1280×720, shows app + logo)

---

---

## Week 3 Integration Points

These are the handoffs between agents that need to be coordinated:

| Handoff | From | To | When |
|---------|------|----|------|
| Resident-friendly string table | Agent 1 | Agent 3 (web demo) | Monday |
| Eval server IP + test confirmation | Agent 2 | Everyone (for reference) | Tuesday |
| First Monte Carlo results | Agent 2 | Agent 4 (writeup data) | Thursday |
| Demo recording screenshots | Agent 4 | Agent 3 (README) | Thursday |
| Video draft link | Agent 4 | All (review) | Friday |

## Week 3 Exit Criteria

By end of Friday April 18:

- [ ] Track A D01/D03 demo flow is polished and demo-ready on iPhone 16
- [ ] Track B B4 duplicate category scenario works cleanly
- [ ] No technical labels visible anywhere in resident-facing UI
- [ ] Eval server running, 20+ run Monte Carlo experiment completed for D01/D03
- [ ] Token budget ablation experiment run and results saved
- [ ] Web demo at feature parity with mobile
- [ ] Video uploaded to YouTube (unlisted, ready for review)
- [ ] Kaggle writeup draft complete
- [ ] Repository structure complete with README, ARCHITECTURE.md, paper outlines
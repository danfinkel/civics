# CivicLens — 4-Week Build Plan

**Version 1.0 | April 2026**  
**Stack:** Flutter (iOS + Android) + Gemma 4 E2B on-device (MediaPipe)  
**Web Demo:** Hugging Face Spaces (Gradio, E4B via Ollama)  
**Agents:** Claude Code (parallel agent development)  
**Design:** Google Stitch for UI component generation

---

## Repository Structure

```
civiclens/
├── README.md
├── ARCHITECTURE.md
├── mobile/                          # Flutter app
│   ├── lib/
│   │   ├── main.dart
│   │   ├── core/
│   │   │   ├── inference/           # Gemma 4 inference engine
│   │   │   │   ├── gemma_client.dart
│   │   │   │   ├── prompt_templates.dart
│   │   │   │   └── response_parser.dart
│   │   │   ├── imaging/             # Image pipeline
│   │   │   │   ├── blur_detector.dart
│   │   │   │   ├── image_processor.dart
│   │   │   │   └── document_capture.dart
│   │   │   └── models/              # Data models
│   │   │       ├── track_a_result.dart
│   │   │       └── track_b_result.dart
│   │   ├── features/
│   │   │   ├── track_a/             # SNAP Proof-Pack
│   │   │   │   ├── track_a_screen.dart
│   │   │   │   ├── track_a_controller.dart
│   │   │   │   └── widgets/
│   │   │   └── track_b/             # BPS Packet Checker
│   │   │       ├── track_b_screen.dart
│   │   │       ├── track_b_controller.dart
│   │   │       └── widgets/
│   │   └── shared/
│   │       ├── widgets/             # Shared UI components
│   │       ├── theme/               # Design system
│   │       └── utils/
│   ├── test/
│   └── pubspec.yaml
├── web_demo/                        # Hugging Face Spaces demo
│   ├── app.py                       # Gradio app
│   ├── prompts.py                   # Shared prompt templates
│   ├── inference.py                 # E4B via Ollama
│   └── requirements.txt
├── spike/                           # All spike research (existing)
│   ├── docs/
│   ├── artifacts/
│   └── scripts/
└── docs/
    ├── VISION.md                    # Product vision (this file's companion)
    ├── ARCHITECTURE.md              # Architecture decisions
    └── SPIKE_SUMMARY.md             # Key spike findings for agents
```

---

## Architecture Overview

### On-Device Inference (Mobile)

```
Phone Camera / File Picker
        ↓
Image Pre-processor (100 DPI JPEG, normalize)
        ↓
Blur Detector (Laplacian variance, OpenCV)
        ↓ [blur score < threshold]
"Retake" prompt to resident      
        ↓ [blur score ≥ threshold]
Gemma 4 E2B (MediaPipe LLM Inference API)
        ↓
JSON Response Parser + Retry Wrapper
        ↓
Confidence Triage (high/medium/low)
        ↓
Results UI + Action Summary
```

### Web Demo (Hugging Face Spaces)

```
Gradio File Upload
        ↓
Same image pre-processing pipeline (Python/Pillow)
        ↓
Gemma 4 E4B (Ollama local or hosted)
        ↓
Same JSON parser + retry wrapper
        ↓
Gradio results display
```

### Key Architectural Decisions (from spike)

| Decision | Rationale | Spike Finding |
|----------|-----------|---------------|
| On-device inference | Documents never leave phone | Privacy-first design principle |
| E2B for mobile | Fits in 6GB RAM on modern phones | E4B requires 4GB+ dedicated |
| E4B for web demo | Better accuracy on degraded images | Day 1: E4B +34 point recovery vs E2B |
| Blur detection pre-processing | Model cannot self-report illegibility | Day 3 A6: hallucinates with 0.9 confidence on blurry images |
| JSON retry wrapper | E4B occasionally omits braces | Day 1: parse failure without wrapper |
| Human-in-loop, never auto-approve | Missing-item recall 50–67% | Day 3: model optimistic, action_summary does heavy lifting |
| Track B primary | Higher accuracy, cleaner UX | Day 3: Track B 85.9% vs Track A 66.7% |
| Confidence triage | Calibration imperfect on edge cases | Day 2: D07 high confidence wrong assessment |

---

## Prompt Templates (from spike Day 3)

### Track A — SNAP Proof-Pack Builder

```
You are helping a Massachusetts resident prepare documents for a
SNAP recertification or verification request.

The resident has shared:
1. A government notice (image attached)
2. The following documents they have at home (images attached):
[DOCUMENT_LIST]

Your job:

Step 1: Read the notice and identify what proof categories are
being requested and the response deadline.

Step 2: For each document, classify it and assess whether it
likely satisfies one of the requested categories.

Step 3: Return a structured JSON result:

{
  "notice_summary": {
    "requested_categories": [],
    "deadline": "",
    "consequence": ""
  },
  "proof_pack": [
    {
      "category": "",
      "matched_document": "[document name or MISSING]",
      "assessment": "likely_satisfies|likely_does_not_satisfy|missing|uncertain",
      "confidence": "high|medium|low",
      "evidence": "[quote from document]",
      "caveats": ""
    }
  ],
  "action_summary": "[one paragraph in plain language for the resident]"
}

Important: never state or imply that a document is accepted by
the agency. Use 'appears to satisfy' and 'likely matches' only.
Always show caveats when confidence is not high.
If the notice image is blurry or you cannot clearly read the text,
set notice_summary fields to "UNCERTAIN" — do not guess.
```

### Track B — BPS Packet Checker

```
You are helping a family prepare their Boston Public Schools
registration packet.

The BPS registration checklist requires:
- Proof of child's age (birth certificate or passport)
- TWO proofs of Boston residency from DIFFERENT categories.
  Valid categories: lease/deed, utility bill, bank statement,
  government mail, employer letter, notarized affidavit.
  Two documents from the same category count as only ONE proof.
  If both documents are leases, set duplicate_category_flag to true.
- Current immunization record
- Grade-level indicator (most recent report card or transcript,
  if applicable)

The family has uploaded the following documents (images attached):
[DOCUMENT_LIST]

Return JSON:
{
  "requirements": [
    {
      "requirement": "",
      "status": "satisfied|questionable|missing",
      "matched_document": "[document name or MISSING]",
      "evidence": "[quote or observation]",
      "notes": ""
    }
  ],
  "duplicate_category_flag": true|false,
  "duplicate_category_explanation": "",
  "family_summary": "[plain language: what to bring, what to replace]"
}

If a document is a phone bill or cell phone statement, set its
residency status to "questionable" — acceptance varies by BPS policy.
Important: never state that the packet guarantees registration
or school assignment.
```

---

## Sprint 1 — Week 1: Foundation (April 7–11)

**Goal:** All four infrastructure modules working independently. No integration yet. End of week: each agent can demo their module in isolation.

**Agents run fully in parallel this week.**

---

### Agent 1 — Flutter App Scaffold + Image Pipeline

**Owns:** `mobile/lib/core/imaging/`, `mobile/lib/main.dart`, `mobile/pubspec.yaml`

**Deliverables:**
1. Flutter project initialized with correct dependencies
2. Camera capture + file picker working on iOS and Android
3. Image pre-processor: resize to max 1024px, convert to JPEG at quality 85
4. Blur detector implemented and tested
5. Document capture screen with retake flow

**pubspec.yaml dependencies to include:**
```yaml
dependencies:
  flutter:
    sdk: flutter
  camera: ^0.10.5
  image_picker: ^1.0.4
  image: ^4.1.3
  google_mlkit_commons: ^0.6.0  # For blur detection utilities
  path_provider: ^2.1.1
  
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
```

**Blur detector spec (`blur_detector.dart`):**
```dart
// Uses Laplacian variance method
// Input: File (JPEG image)
// Output: BlurResult { score: double, isBlurry: bool, guidance: String }
// Threshold: score < 100.0 = blurry (tune in week 2 testing)
// Guidance strings:
//   - "Image is clear" (score ≥ 100)
//   - "Try holding your phone steady" (score 50–99)
//   - "Move to better lighting and try again" (score < 50)
```

**Image processor spec (`image_processor.dart`):**
```dart
// Input: File (any image format)
// Output: Uint8List (JPEG bytes, max 1024px longest edge, quality 85)
// Must strip EXIF data (privacy)
// Must normalize rotation from EXIF orientation
```

**Document capture screen spec:**
- Camera viewfinder with document frame overlay
- "Take Photo" and "Choose from Library" options
- After capture: show preview with "Use This" / "Retake" buttons
- If blur detector returns isBlurry=true: show guidance text, disable "Use This" button
- Blur score displayed as debug info in development builds only

**Acceptance criteria:**
- Camera works on iOS simulator and Android emulator
- Blur detector correctly flags a deliberately blurry test image
- Pre-processor reduces a 4000×3000 phone photo to ≤1024px longest edge
- EXIF data stripped from output

---

### Agent 2 — Gemma 4 Inference Engine

**Owns:** `mobile/lib/core/inference/`

**Deliverables:**
1. MediaPipe LLM Inference API integrated for E2B
2. Prompt template system for Track A and Track B
3. Multi-image input support
4. JSON response parser with retry wrapper
5. Confidence parser

**MediaPipe integration:**
```yaml
# Add to pubspec.yaml
google_generative_ai: ^0.4.3
# OR for MediaPipe direct:
# mediapipe_genai: ^0.1.0  (check latest)
```

**GemmaClient spec (`gemma_client.dart`):**
```dart
class GemmaClient {
  // Initialize with model path (E2B, downloaded to device)
  // Model download: ~2.5GB, prompt user on first launch
  
  Future<GemmaResponse> chat({
    required String prompt,
    required List<Uint8List> images,  // list of JPEG bytes
    double temperature = 0.0,
    int maxTokens = 2048,
  });
  
  // GemmaResponse { rawText: String, elapsed: Duration }
}
```

**Prompt templates spec (`prompt_templates.dart`):**
```dart
class PromptTemplates {
  static String trackA({required List<String> documentLabels});
  // Returns full Track A prompt with [DOCUMENT_LIST] substituted
  // documentLabels: ["Document 1: pay stub", "Document 2: lease agreement"]
  
  static String trackB({required List<String> documentLabels});
  // Returns full Track B prompt with [DOCUMENT_LIST] substituted
}
```

**Response parser spec (`response_parser.dart`):**
```dart
class ResponseParser {
  // Parse Track A response
  static TrackAResult? parseTrackA(String raw);
  
  // Parse Track B response  
  static TrackBResult? parseTrackB(String raw);
  
  // Internal: try parse, if fail try wrapping in {}, if fail return null
  static Map<String, dynamic>? _parseWithRetry(String raw);
}
```

**JSON retry wrapper logic (from spike day1_extract.py):**
1. Try `json.decode(raw)` directly
2. If fails, try `json.decode('{' + raw.trim() + '}')`
3. If fails, try stripping markdown fences then parse
4. If all fail, return null → trigger error state in UI

**Confidence mapping:**
```dart
enum ConfidenceLevel { high, medium, low, uncertain }
// "high" → ConfidenceLevel.high
// "medium" → ConfidenceLevel.medium  
// "low" → ConfidenceLevel.low
// null / missing / "uncertain" → ConfidenceLevel.uncertain
```

**Acceptance criteria:**
- GemmaClient successfully loads E2B model on device
- Multi-image prompt sends correctly to MediaPipe API
- Retry wrapper correctly handles bare key:value output (no braces)
- Parser correctly extracts TrackAResult and TrackBResult from valid JSON

---

### Agent 3 — Web Demo (Hugging Face Spaces)

**Owns:** `web_demo/`

**Deliverables:**
1. Gradio app running locally
2. Track A and Track B flows implemented
3. Confidence visualization working
4. Deployed to Hugging Face Spaces with stable URL

**`app.py` structure:**
```python
import gradio as gr
from inference import run_track_a, run_track_b
from display import format_track_a_results, format_track_b_results

# Track A interface
track_a = gr.Interface(
    fn=run_track_a,
    inputs=[
        gr.File(label="Government Notice", file_types=["image", ".pdf"]),
        gr.File(label="Document 1", file_types=["image", ".pdf"]),
        gr.File(label="Document 2 (optional)", file_types=["image", ".pdf"]),
        gr.File(label="Document 3 (optional)", file_types=["image", ".pdf"]),
    ],
    outputs=[
        gr.JSON(label="Structured Result"),
        gr.Markdown(label="Action Summary"),
        gr.HTML(label="Proof Pack"),  # color-coded grid
    ],
)

# Track B interface — same pattern
```

**`inference.py` spec:**
```python
def run_track_a(notice_file, doc1, doc2=None, doc3=None) -> tuple[dict, str, str]:
    # 1. Pre-process all images (100 DPI JPEG via Pillow)
    # 2. Run blur detection on each image
    # 3. Build document label list from non-None inputs
    # 4. Call Ollama gemma4:e4b with Track A prompt
    # 5. Parse JSON with retry wrapper
    # 6. Return (parsed_json, action_summary, html_proof_pack)

def run_track_b(doc1, doc2, doc3=None, doc4=None) -> tuple[dict, str, str]:
    # Same pattern for Track B
```

**Confidence color coding:**
- `high` → green background (`#F0FDF4`)
- `medium` → amber background (`#FFFBEB`)
- `low` / `uncertain` → red background (`#FFF3F3`)
- `missing` → gray background (`#F8FAFC`) with "MISSING" label

**Acceptance criteria:**
- Gradio app runs locally with `python app.py`
- Track A correctly processes D01 notice + D03 pay stub and returns proof pack
- Track B correctly processes D12 + D05 + D06 + D13 and returns satisfied packet
- Deployed to Hugging Face Spaces at a public URL
- Works on mobile browser (test from phone)

---

### Agent 4 — Design System (Google Stitch)

**Owns:** `docs/design/`, design specs for Agents 1 and 3

**Deliverables:**
1. Core color palette and typography
2. Document upload screen design
3. Processing/loading state design
4. Results screen design (Track A proof pack grid)
5. Results screen design (Track B requirements checklist)
6. Action summary component design
7. Blur detection warning component

**Design prompts for Google Stitch:**

*Screen 1 — Home / Track Selection:*
> "Design a clean, minimal mobile home screen for a civic document assistant app called CivicLens. Two large cards: 'SNAP Benefits' and 'School Enrollment'. Each card has a brief description and an arrow. The app helps low-income residents organize government documents. Tone: trustworthy, accessible, not corporate. Colors: dark navy (#1A3A5C) for primary, white background, clear typography. No gradients, no decorative elements. The design should feel like a government tool, not a consumer app."

*Screen 2 — Document Upload:*
> "Design a document upload screen for CivicLens mobile app. Shows a numbered list of document slots (e.g. '1. Government Notice', '2. Pay Stub', '3. Optional document'). Each slot has a camera icon button and a file picker button. Completed slots show a thumbnail with a green checkmark. A 'Analyze Documents' button appears when at least the required slots are filled. Include a blur warning state where a slot shows an amber warning icon with the text 'Photo unclear — retake?'"

*Screen 3 — Results (Track B):*
> "Design a results screen for CivicLens showing BPS school enrollment packet status. Four requirement rows: 'Proof of Age', 'Residency Proof 1', 'Residency Proof 2', 'Immunization Record'. Each row has a status badge: green 'Satisfied', amber 'Questionable', or gray 'Missing'. Below the rows, a plain-language 'What to do next' section in a light blue card. A duplicate category warning banner in amber if triggered. Navigation: back arrow, share button."

*Screen 4 — Confidence display:*
> "Design a confidence indicator component for CivicLens. Three states: green check with 'High confidence', amber caution with 'Review recommended', red X with 'Please verify'. Each state shows a brief explanation below the icon. Used inline in results rows. Small, fits in a list item."

**Acceptance criteria:**
- All 4 screen designs exported as PNG references
- Color palette documented as hex values
- Typography hierarchy documented (font sizes for h1/h2/body/caption)
- Design specs delivered to Agent 1 (mobile) and Agent 3 (web) by end of week 1

---

## Sprint 2 — Week 2: Track B MVP (April 14–18)

**Goal:** Complete Track B end-to-end on mobile. Demo scenario B1 (complete valid packet) working on a real phone by Friday.

**Dependency:** Agent 2's inference engine must be complete before Agents 1 and 3 can integrate this week.

**Parallelization:** Agent 1 (mobile Track B UI) and Agent 3 (web demo polish) run in parallel. Agent 2 supports integration.

---

### Agent 1 — Mobile Track B UI + Integration

**Deliverables:**
1. Multi-document upload flow for Track B (4 document slots)
2. Track B inference integration
3. Requirements checklist results screen
4. Action summary display
5. Duplicate category flag UI
6. Phone bill "questionable" visual treatment

**Track B upload flow:**
- Screen title: "School Enrollment Packet"
- Slot 1: "Proof of Age" (required) — accepts birth certificate or passport
- Slot 2: "Residency Proof 1" (required)
- Slot 3: "Residency Proof 2" (required)
- Slot 4: "Immunization Record" (required)
- Slot 5: "Grade Indicator" (optional) — show/hide toggle
- Each slot: camera button + library button + blur check on capture
- "Check My Packet" CTA button — disabled until all required slots filled

**Requirements display spec:**
```dart
// TrackBResultsScreen shows:
// 1. Requirements checklist (4 rows)
//    - Requirement name
//    - Status badge (satisfied/questionable/missing)
//    - Matched document name
//    - Notes (if any)
// 2. Duplicate category warning (if duplicate_category_flag = true)
//    - Amber banner: "Two leases count as one proof — you need a second document type"
// 3. Action summary card
//    - Plain language text from family_summary field
//    - Prominent placement, large readable font
// 4. "Start Over" button
```

**Data models (`track_b_result.dart`):**
```dart
class TrackBResult {
  final List<RequirementResult> requirements;
  final bool duplicateCategoryFlag;
  final String duplicateCategoryExplanation;
  final String familySummary;
  final ConfidenceLevel overallConfidence;
}

class RequirementResult {
  final String requirement;
  final RequirementStatus status;  // satisfied, questionable, missing
  final String matchedDocument;
  final String evidence;
  final String notes;
  final ConfidenceLevel confidence;
}
```

**Acceptance criteria:**
- B1 scenario (D12 + D05 + D06 + D13) returns 4 satisfied requirements
- B4 scenario (D12 + D05 + D14 + D13) correctly shows duplicate category warning
- B7 scenario (D12 + D05 + D07 + D13) shows D07 as "questionable"
- B8 scenario (D09 only) shows all 4 requirements as missing
- Action summary is displayed prominently and is readable

---

### Agent 2 — Integration Support + E2B Fallback

**Deliverables:**
1. E2B model download flow for first launch
2. Model size warning and download progress
3. Fallback to API mode if on-device inference fails (for demo reliability)
4. Performance profiling on real devices

**First launch flow:**
```
App opens for first time
        ↓
"CivicLens uses AI to analyze your documents privately on your device.
 This requires a one-time download of 2.5GB. 
 Connect to WiFi recommended."
[Download Now] [Use Cloud Mode Instead]
        ↓
Download progress bar
        ↓
"Ready — your documents stay on your device"
```

**Fallback mode:** If E2B inference fails (out of memory, model not downloaded), route to web demo API with explicit consent prompt: "To analyze this document, CivicLens needs to send it to a secure server. Your document will not be stored. Continue?"

**Performance targets:**
- E2B inference on 3-4 document images: ≤45 seconds on iPhone 13 or equivalent
- If >60 seconds: show progress indicator with "Analyzing your documents..."
- If >120 seconds: offer to retry in cloud mode

---

### Agent 3 — Web Demo Track B Polish

**Deliverables:**
1. Track B fully working on web demo
2. Confidence color coding applied to all results
3. Duplicate category warning visible
4. Mobile browser tested and working
5. Hugging Face Spaces URL confirmed stable

---

### Agent 4 — Video Script + Demo Scenarios

**Deliverables:**
1. 3-minute video script drafted
2. Demo scenarios B1 and B4 prepared with real synthetic documents
3. Screen recording setup ready

**Video script structure (3 minutes):**

*0:00–0:30 — The problem (no product yet)*
Show: text/animation only
Script: "Every year, families applying for SNAP benefits or enrolling children in school face the same challenge: gathering the right documents, by the right deadline, in the right combination. Miss a requirement and you start over. The instructions exist — but understanding whether what you have is what is needed requires expertise most families don't have access to."

*0:30–1:00 — Our approach*
Show: spike methodology overview, brief
Script: "Before building, we spent a week rigorously testing whether Gemma 4 could reliably handle civic documents — pay stubs, leases, government notices, birth certificates. We ran over 100 experiments, measured failure modes, and designed the product around what we learned."

*1:00–2:15 — Demo (Track B)*
Show: screen recording, real app
Script: Narrate the B1 scenario. Family uploads birth certificate, lease, utility bill, immunization record. App processes on-device. Shows all four requirements satisfied. Then show B4: swap in second lease, app flags duplicate category violation.

*2:15–2:45 — Privacy architecture*
Show: architecture diagram
Script: "Every document is processed entirely on device using Gemma 4 E2B. Nothing is uploaded. For a resident submitting a birth certificate and a state ID, that matters."

*2:45–3:00 — Call to action*
Show: app on phone
Script: "CivicLens. Documents stay on your phone. Help gets to the people who need it."

---

## Sprint 3 — Week 3: Track A + Blur Detection (April 21–25)

**Goal:** Track A working end-to-end. Blur detection integrated into production flow. Both tracks demoable.

---

### Agent 1 — Mobile Track A UI + Integration

**Deliverables:**
1. Notice upload as first step (Track A specific)
2. Supporting documents upload (up to 3)
3. Track A inference integration
4. Proof pack grid results screen
5. Deadline display (prominent, near top of results)
6. Missing item highlighting

**Track A upload flow:**
- Step 1: "Upload your government notice" — single slot, required
- Step 2: "Upload your documents" — up to 3 slots, at least 1 required
- Notice is always image 0 in the multi-image request
- Documents are labeled "Document 1", "Document 2", "Document 3"

**Proof pack grid spec:**
```dart
// ProofPackScreen shows:
// 1. Notice summary card (deadline prominent in large text, consequence below)
// 2. Proof pack grid — one row per requested category:
//    - Category name
//    - Matched document (or "MISSING" in red)
//    - Assessment badge (likely_satisfies / likely_does_not_satisfy / missing / uncertain)
//    - Caveats (if any, shown in amber)
// 3. Action summary card
```

**Data models (`track_a_result.dart`):**
```dart
class TrackAResult {
  final NoticeSummary noticeSummary;
  final List<ProofPackItem> proofPack;
  final String actionSummary;
}

class NoticeSummary {
  final List<String> requestedCategories;
  final String deadline;  // Display as-is from model
  final String consequence;
}

class ProofPackItem {
  final String category;
  final String matchedDocument;
  final AssessmentLabel assessment;
  final ConfidenceLevel confidence;
  final String evidence;
  final String caveats;
}

enum AssessmentLabel {
  likelySatisfies,
  likelyDoesNotSatisfy,
  missing,
  uncertain
}
```

**Spike-informed edge case handling:**
- If `deadline` = "UNCERTAIN": show amber banner "Notice unclear — please contact DTA at (617) 348-8400"
- If `assessment` = `likelyDoesNotSatisfy` and caveats mention "date": show "This document may be too old" tooltip
- If `matchedDocument` = "MISSING": show red "MISSING" badge and include in action summary count

**Acceptance criteria:**
- A1 scenario: D01 notice + D03 pay stub → income satisfied
- A3 scenario: D01 notice + D04 stale stub → income not satisfied with date caveat
- A6 scenario: D01-blurry → UNCERTAIN notice fields, amber banner shown
- A7 scenario: D01 + D10 award letter → income not satisfied, clear explanation

---

### Agent 2 — Blur Detection Production Integration

**Deliverables:**
1. Blur detector integrated into document capture flow for both tracks
2. Quality threshold tuned from real-world testing
3. Retake guidance text finalized
4. Blur detection metrics logged for debugging

**Blur detection implementation:**

The Laplacian variance method computes the variance of the Laplacian of the image. Low variance = blurry. Implementation in Flutter using the `image` package:

```dart
double computeBlurScore(img.Image image) {
  // Convert to grayscale
  final gray = img.grayscale(image);
  
  // Apply Laplacian kernel
  // [0, 1, 0, 1, -4, 1, 0, 1, 0]
  final laplacian = img.convolution(gray, 
    filter: [0, 1, 0, 1, -4, 1, 0, 1, 0],
    div: 1,
  );
  
  // Compute variance
  double mean = 0;
  int count = 0;
  for (int y = 0; y < laplacian.height; y++) {
    for (int x = 0; x < laplacian.width; x++) {
      mean += img.getLuminance(laplacian.getPixel(x, y));
      count++;
    }
  }
  mean /= count;
  
  double variance = 0;
  for (int y = 0; y < laplacian.height; y++) {
    for (int x = 0; x < laplacian.width; x++) {
      final diff = img.getLuminance(laplacian.getPixel(x, y)) - mean;
      variance += diff * diff;
    }
  }
  return variance / count;
}

// Thresholds (tune in week 3):
// score < 50: very blurry — "Move to better lighting, hold phone steady"
// score 50–100: moderately blurry — "Try holding your phone steady"  
// score > 100: acceptable — proceed to inference
```

**Tuning process:**
- Test against D01-degraded.jpg, D01-blurry.jpg, D01-clean.pdf (converted)
- Blurry variants from spike (generated with Pillow, sigma=2.0–3.0) should score < 50
- Degraded variants (sigma=1.2) should score in range 50–100 (marginal, show warning)
- Clean PDFs should score > 100

---

### Agent 3 — Web Demo Track A + Final Polish

**Deliverables:**
1. Track A fully working on web demo
2. Tabbed interface for Track A / Track B
3. All confidence color coding applied
4. Loading state with "Analyzing documents..." message
5. Error handling for parse failures

---

### Agent 4 — Video Production

**Deliverables:**
1. Screen recordings captured (both tracks)
2. Video edited to ≤3 minutes
3. Uploaded to YouTube (unlisted for review, public for submission)
4. Thumbnail created

**Recording checklist:**
- Track B: B1 scenario (complete valid packet) — the happy path
- Track B: B4 scenario (duplicate category warning) — the interesting case
- Track A: A1 scenario (income notice + pay stub) — clean success
- Track A: A6 scenario (blurry notice → UNCERTAIN) — shows safety architecture
- Architecture slide: on-device inference diagram
- Privacy callout: "Documents never leave your phone"

---

## Sprint 4 — Week 4: Polish, Write-up, Submission (April 28 – May 2)

**Goal:** Everything submitted. Repo clean. Demo live. Video public on YouTube. Writeup under 1,500 words.

**Note:** No new features this week. Bug fixes and polish only.

---

### Agent 1 — App Polish + Edge Cases

**Deliverables:**
1. Loading states for all inference calls
2. Error states (parse failure, model timeout, network error in cloud mode)
3. Empty state handling (no documents uploaded)
4. App icon and splash screen
5. Tested on at minimum: iPhone 14, Pixel 7 (or equivalents)

**Error states:**
- Parse failure: "Couldn't read the results — try taking clearer photos"
- Model timeout (>120s): "Analysis is taking longer than expected. Switch to cloud mode?"
- No documents: "Add at least one document to get started"
- Blur check failure: [show retake guidance, documented above]

---

### Agent 2 — Performance + Final Integration

**Deliverables:**
1. Cold start time ≤3 seconds (after model downloaded)
2. Memory profiling — confirm E2B fits in 4GB RAM
3. Battery impact acceptable for demo duration
4. Final integration test: all 8 Track A + 8 Track B scenarios passing

**Integration test checklist (run all before submission):**
```
Track B:
[ ] B1: complete packet → all satisfied
[ ] B2: missing immunization → missing flagged
[ ] B4: duplicate leases → flag shown
[ ] B5: Spanish utility bill → satisfied
[ ] B6: host family affidavit → satisfied
[ ] B7: phone bill → questionable
[ ] B8: state ID only → all missing

Track A:
[ ] A1: income notice + current pay stub → satisfied
[ ] A2: income notice + wrong docs → missing flagged
[ ] A3: income notice + stale stub → not satisfied with date caveat
[ ] A4: multi-category + full coverage → all satisfied
[ ] A7: income notice + award letter → not satisfied
[ ] A6: blurry notice → UNCERTAIN shown
```

---

### Agent 3 — Repository + Documentation

**Deliverables:**
1. README.md with setup instructions, demo link, video link
2. ARCHITECTURE.md explaining on-device inference decision
3. SPIKE_SUMMARY.md — key findings from feasibility spike
4. Code comments on all inference and image processing code
5. requirements.txt / pubspec.yaml up to date
6. All spike scripts and findings committed to `/spike`

**README.md must include:**
- Project description (2 paragraphs)
- Demo URL (Hugging Face Spaces)
- Video URL (YouTube)
- Setup instructions for local development
- Model download instructions (E2B for mobile, E4B for web demo)
- Architecture diagram
- Link to spike methodology
- Known limitations (from Day 5 decision memo)

**ARCHITECTURE.md must explain:**
- Why on-device inference (privacy rationale, not just technical)
- Why Flutter (cross-platform, performance for image processing)
- Why E2B on device vs E4B on server (capability vs constraints)
- Blur detection design decision (from spike A6 finding)
- JSON retry wrapper (from spike Day 1 E4B finding)
- Human-in-loop rationale (from spike missing-item detection findings)

---

### Agent 4 — Kaggle Writeup (≤1,500 words)

**Structure:**

**Title:** CivicLens: Privacy-First Civic Document Intelligence with On-Device Gemma 4

**Subtitle:** Helping residents navigate SNAP recertification and school enrollment using local multimodal AI

**Section 1 — The Problem (~150 words)**
The document burden on residents navigating government benefit systems. SNAP recertification, school enrollment. Wrong documents mean missed deadlines, lost benefits, delayed enrollment. The problem is interpretation, not access.

**Section 2 — Why On-Device Gemma 4 (~150 words)**
Privacy requirement for sensitive civic documents. Gemma 4 E2B runs on consumer hardware. Multimodal capability handles phone photos. No server required. This is the intersection of the technology's specific strengths and the use case's specific requirements.

**Section 3 — Feasibility Spike Methodology (~300 words)**
Five-day structured spike before building. 16 synthetic documents. 100+ inference experiments. Formal pass/fail thresholds. Key findings: classification 100%, mapping 66–87%, abstention failure on blurry images, missing-item detection 50–67%. Architectural decisions made from evidence.

**Section 4 — Architecture (~250 words)**
On-device inference pipeline. Blur detection pre-processing. Track A (SNAP) and Track B (BPS). JSON retry wrapper. Confidence triage. Human-in-loop, never auto-approve. Flutter for cross-platform mobile.

**Section 5 — Results and Limitations (~250 words)**
What works: classification, mapping, JSON reliability. What does not: precise field extraction, image quality self-assessment. How limitations are addressed: blur detection, confidence flagging, action summary as primary resident output.

**Section 6 — What We Built (~200 words)**
CivicLens demo. Two tracks. Privacy architecture. Spike methodology as foundation for evidence-driven product decisions. Known limitations documented.

**Word budget:** 150 + 150 + 300 + 250 + 250 + 200 = 1,300 words + title/headers ≈ 1,450 total

---

## MCP Tools for the Build Phase

| Tool | Use | When |
|------|-----|------|
| GitHub MCP | Branch management, PRs, commit messages | All weeks |
| Google Stitch | UI component and screen design generation | Week 1 Agent 4 |
| Hugging Face MCP (if available) | Space deployment, model management | Week 1–2 Agent 3 |
| Filesystem MCP | File read/write across agents | All weeks |

**GitHub branch strategy:**
```
main                    # stable, demo-ready at all times
├── sprint-1/           # week 1 branches
│   ├── feature/image-pipeline
│   ├── feature/inference-engine
│   ├── feature/web-demo-scaffold
│   └── feature/design-system
├── sprint-2/track-b-mvp
├── sprint-3/track-a-blur
└── sprint-4/polish
```

Each agent works on its own branch. PRs to main at end of each sprint, after integration testing.

---

## Known Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| E2B inference too slow on device (>60s) | Medium | High | Fallback to cloud mode; pre-load model on WiFi |
| E2B accuracy insufficient vs E4B | Medium | Medium | Cloud mode fallback; demo uses E4B on Spaces |
| MediaPipe API breaking changes | Low | High | Pin to specific version; test week 1 |
| Blur threshold needs tuning | High | Low | Expose threshold in debug settings; tune week 3 |
| Hugging Face Spaces cold start slow | Medium | Low | Keep demo warm with scheduled ping |
| Video exceeds 3 minutes | Medium | Medium | Script timed to 2:45 to allow for edits |
| Kaggle writeup exceeds 1,500 words | Medium | Low | Word budget tracked per section above |

---

## Definition of Done

The submission is complete when all of the following are true:

- [ ] Flutter app runs on iOS and Android with E2B on-device inference
- [ ] All 8 Track B scenarios pass integration test
- [ ] All 6 Track A scenarios pass integration test
- [ ] Blur detection correctly flags blurry images
- [ ] Web demo deployed at stable public URL (Hugging Face Spaces)
- [ ] 3-minute video uploaded to YouTube (public, no login required)
- [ ] GitHub repo public, README complete, all spike findings committed
- [ ] Kaggle writeup submitted (≤1,500 words)
- [ ] Cover image attached to Kaggle submission
- [ ] All submission checklist items from hackathon requirements met
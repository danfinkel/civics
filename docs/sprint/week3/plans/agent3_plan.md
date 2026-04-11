# Agent 3 — Week 3 Plan: Web Demo Parity + Research Repository Foundation

**Week:** April 14–18, 2026  
**Owns:** `web_demo/`, `docs/`, `README.md`, `ARCHITECTURE.md`, `spike/` organization  
**Goal:** Two deliverables: (1) HF Spaces web demo at feature parity with mobile, (2) repository foundation supporting Kaggle writeup and research papers.

---

## Monday: Web Demo Track A Parity

### Morning (3 hours)
**Review current web demo state**

Read `web_demo/app.py` (or equivalent) to understand current implementation.

**Add Track A notice-first flow:**

Current state likely treats all documents equally. Update to:
1. User selects "SNAP Benefits" → enters Track A flow
2. First upload slot is for the DTA notice (D01)
3. Subsequent slots for supporting documents (D03, D04, etc.)
4. Blur detection runs on all uploads

**Implement blur detection preprocessing:**

```python
import cv2
import numpy as np

def detect_blur(image_bytes: bytes, threshold: float = 100.0) -> tuple[bool, float]:
    """Returns (is_blurry, variance_score)."""
    nparr = np.frombuffer(image_bytes, np.uint8)
    img = cv2.imdecode(nparr, cv2.IMREAD_GRAYSCALE)
    if img is None:
        return True, 0.0
    
    # Laplacian variance for blur detection
    laplacian_var = cv2.Laplacian(img, cv2.CV_64F).var()
    is_blurry = laplacian_var < threshold
    return is_blurry, laplacian_var
```

**Add to upload handler:**
```python
is_blurry, blur_score = detect_blur(image_bytes)
if is_blurry:
    # Show warning but allow override
    return {
        "status": "blurry_warning",
        "blur_score": blur_score,
        "message": "This image appears blurry. Results may be less accurate."
    }
```

### Afternoon (2 hours)
**Track A results: deadline banner**

Update results display to match mobile:

```python
def render_track_a_results(result: dict) -> str:
    deadline = result.get('notice_summary', {}).get('deadline', '')
    consequence = result.get('notice_summary', {}).get('consequence', '')
    
    html = ""
    
    # Deadline banner (if present and not UNCERTAIN)
    if deadline and deadline != 'UNCERTAIN':
        html += f"""
        <div style="background-color: #FFF3F3; border: 2px solid #B71C1C; 
                    border-radius: 8px; padding: 16px; margin-bottom: 16px;">
            <div style="font-size: 18px; font-weight: bold; color: #B71C1C;">
                Respond by {deadline}
            </div>
            {f'<div style="font-size: 14px; color: #555555; margin-top: 4px;">{format_consequence(consequence)}</div>' if consequence else ''}
        </div>
        """
    elif deadline == 'UNCERTAIN':
        # A6 handling
        html += """
        <div style="background-color: #FFFBEB; border: 2px solid #B45309;
                    border-radius: 8px; padding: 16px; margin-bottom: 16px;">
            <div style="font-size: 16px; font-weight: bold; color: #92400E;">
                Notice is unclear
            </div>
            <div style="font-size: 14px; color: #1A1A1A; margin-top: 8px;">
                We couldn't clearly read the deadline on this notice. 
                Contact DTA at the number on your notice to confirm your response date.
            </div>
        </div>
        """
    
    return html
```

---

## Tuesday: Web Demo Track B Parity + LabelFormatter

### Morning (3 hours)
**Receive LabelFormatter mapping from Agent 1**

Use the same resident-friendly string table:

| Technical label | Resident-friendly display string |
|----------------|--------------------------------|
| `likely_satisfies` | "Appears to meet this requirement" |
| `likely_does_not_satisfy` | "May not meet this requirement" |
| `insufficient_information` | "Unclear — needs review" |
| `missing` | "Not found in your documents" |
| `questionable` | "Accepted by some offices — check with yours" |
| `residency_ambiguous` | "Acceptance varies by office" |
| `invalid_proof` | "This type of document is not accepted" |
| `same_residency_category_duplicate` | "Same type as another document you submitted" |

**Implement in web demo:**

```python
ASSESSMENT_LABELS = {
    'likely_satisfies': 'Appears to meet this requirement',
    'likely_does_not_satisfy': 'May not meet this requirement',
    'insufficient_information': 'Unclear — needs review',
    'missing': 'Not found in your documents',
    'questionable': 'Accepted by some offices — check with yours',
    'residency_ambiguous': 'Acceptance varies by office',
    'invalid_proof': 'This type of document is not accepted',
    'same_residency_category_duplicate': 'Same type as another document you submitted',
    'satisfied': 'Looks good',
}

def format_assessment(raw: str) -> str:
    return ASSESSMENT_LABELS.get(raw.lower(), raw)
```

**Apply to all results displays** — no technical labels visible anywhere.

### Afternoon (2 hours)
**Track B duplicate category warning**

```python
def render_track_b_results(result: dict) -> str:
    html = ""
    
    # Duplicate category warning (unmissable)
    if result.get('duplicate_category_flag'):
        html += """
        <div style="background-color: #FFFBEB; border: 2px solid #B45309;
                    border-radius: 8px; padding: 16px; margin-bottom: 16px;">
            <div style="font-size: 16px; font-weight: bold; color: #92400E;">
                Two documents from the same category
            </div>
            <div style="font-size: 14px; color: #1A1A1A; margin-top: 8px;">
                You submitted two leases. BPS requires documents from two 
                different categories — for example, a lease AND a utility bill. 
                A second lease does not count as a second proof.
            </div>
        </div>
        """
    
    # Family summary (prominent)
    family_summary = result.get('family_summary', '')
    if family_summary:
        html += f"""
        <div style="background-color: #F0FDF4; border-radius: 8px; padding: 16px; 
                    margin-bottom: 16px; font-size: 16px;">
            {family_summary}
        </div>
        """
    
    return html
```

**Phone bill questionable treatment:**
- When document type is "phone_bill", show amber "questionable" status
- Display: "Accepted by some offices — check with yours"

---

## Wednesday: HF Spaces Reliability + Repository Structure

### Morning (3 hours)
**Add `/health` endpoint to web demo:**

```python
from flask import Flask, jsonify

app = Flask(__name__)

@app.route('/health')
def health():
    return jsonify({'status': 'ok', 'timestamp': datetime.now().isoformat()})
```

**Create keep-warm GitHub Actions workflow:**

Create `.github/workflows/keep-warm.yml`:

```yaml
name: Keep HF Spaces Warm

on:
  schedule:
    # Every 30 minutes during business hours (9am-6pm ET, Mon-Fri)
    - cron: '*/30 13-23 * * 1-5'
  workflow_dispatch:

jobs:
  ping:
    runs-on: ubuntu-latest
    steps:
      - name: Ping HF Spaces
        run: |
          curl -sSf https://DanFinkel-civiclens.hf.space/health || echo "Ping failed"
```

**Test cold start time:**
- Document in README: "Cold start: ~X seconds"
- If >90 seconds, add loading message to UI

### Afternoon (2 hours)
**Organize repository structure:**

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

Create directories:
```bash
mkdir -p research/papers/nlp_ai research/papers/civic_tech
mkdir -p .github/workflows
# Ensure spike/docs/ exists with proper organization
```

---

## Thursday: README.md + ARCHITECTURE.md

### Morning (3 hours)
**Write `README.md`**

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

### Mobile app (iOS)

```bash
cd mobile
./scripts/dev_deploy.sh
```

### Web demo (local)

```bash
cd web_demo
pip install -r requirements.txt
python app.py
```

### Evaluation server

```bash
# On iPhone
./scripts/dev_deploy.sh --eval

# On Mac
export PHONE_IP=192.168.1.X
python research/eval/runner.py --artifacts D01,D03 --runs 20
```

## Known Limitations

- Field-level extraction: ~40% hallucination rate on complex tabular layouts
  (pay stubs with adjacent current/YTD columns). Mitigated by human review UX.
- Image quality: model cannot self-report illegibility. Mitigated by blur 
  detection pre-processing.
- Missing-item detection: 50-67% recall. Mitigated by action summary guidance.

## Research

Two papers in progress:
- NLP/AI track: On-device multimodal LLM performance for civic document understanding
- Civic tech track: Privacy-first document intelligence for government service navigation

## License

Apache 2.0
```

### Afternoon (2 hours)
**Write `ARCHITECTURE.md`**

```markdown
# CivicLens Architecture

## Overview

CivicLens is a privacy-first mobile application for civic document intelligence.
It uses on-device inference to analyze government notices and supporting documents,
helping residents verify their document packets before submission.

## Core Principles

1. **Privacy by design:** Documents never leave the device
2. **Evidence-driven:** Built on a structured feasibility spike
3. **Human-in-loop:** Never auto-approve; always show reasoning
4. **Graceful degradation:** Known model limitations addressed via UX

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        iPhone 16                            │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────┐  │
│  │   Camera    │───▶│  ML Kit OCR │───▶│  llama.cpp E2B  │  │
│  │   / Photos  │    │   (391ms)   │    │   (11.9s)       │  │
│  └─────────────┘    └─────────────┘    └─────────────────┘  │
│                                                 │           │
│  ┌──────────────────────────────────────────────┘           │
│  ▼                                                          │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────┐  │
│  │   Gemma 4   │───▶│ JSON Parser │───▶│  Results Screen │  │
│  │   (4B E2B)  │    │  (retry +   │    │  (resident-     │  │
│  │   2.9GB     │    │   fallback) │    │   friendly)     │  │
│  └─────────────┘    └─────────────┘    └─────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │  HF Spaces Demo │
                    │  (cloud fallback)│
                    └─────────────────┘
```

## Key Technical Decisions

### On-device inference (llama.cpp + Metal)

**Decision:** Use llama.cpp with Metal GPU acceleration for Gemma 4 E2B.

**Rationale:**
- Privacy requirement: documents cannot leave device
- Gemma 4 Apache 2.0 license allows commercial deployment
- E2B (2 billion active parameters) fits in mobile memory
- Metal provides ~3x speedup vs CPU-only

**Tradeoffs:**
- 2.9GB model download (one-time)
- 15s inference latency (acceptable for the use case)
- No batching possible (single-user device)

### Blur detection preprocessing

**Decision:** Run Laplacian variance blur detection before OCR.

**Rationale:**
- Spike finding A6: model cannot self-report illegibility
- False confidence on blurry images is dangerous for civic documents
- Warning + override preserves user agency

**Implementation:**
```dart
// OpenCV Laplacian variance
final laplacianVar = cv.Laplacian(grayImage, cv.CV_64F).var();
final isBlurry = laplacianVar < threshold;
```

### JSON retry wrapper

**Decision:** Wrap LLM output with multiple parsing strategies.

**Rationale:**
- Spike finding: ~5% of outputs have markdown fences or partial JSON
- Retry with fence stripping before failing
- Fallback to "uncertain" state rather than crash

**Implementation:**
```dart
String? parseWithRetry(String raw) {
  // Try direct parse
  // Try stripping markdown fences
  // Try wrapping bare output
  // Return null if all fail
}
```

### FFI struct alignment

**Decision:** Patch Dart FFI definitions to match native llama.cpp structs.

**Rationale:**
- Original `llama_cpp_dart` had ABI mismatches
- Struct field offsets must match exactly
- Required for stable initialization

**Files modified:**
- `mobile/lib/ffi/llama_bindings.dart` — struct definitions

## Data Flow

### Track A (SNAP Benefits)

1. User photographs DTA notice
2. Blur detection → ML Kit OCR → text extraction
3. LLM extracts: deadline, consequence, requested categories
4. User photographs supporting documents
5. Each document: blur → OCR → classification → category mapping
6. Proof pack assembled: requirement × document assessment
7. Action summary generated

### Track B (School Enrollment)

1. User photographs up to 4 documents
2. Each: blur → OCR → classification
3. Category mapping for residency proofs
4. Duplicate category detection (same address = same category)
5. Requirement satisfaction matrix
6. Family summary generated

## Eval Server (Debug Mode)

For systematic performance measurement, the app can run in eval mode:

```bash
flutter run --dart-define=EVAL_MODE=true
```

This exposes HTTP endpoints on port 8080:
- `GET /health` — server status
- `POST /infer` — single inference request
- `GET /metrics` — memory and inference count

Used by `research/eval/runner.py` for Monte Carlo experiments.

## File Organization

```
mobile/
├── lib/
│   ├── core/           # Config, constants
│   ├── features/       # Track A, Track B flows
│   ├── shared/         # LabelFormatter, utils
│   ├── eval/           # Eval server (debug only)
│   └── ffi/            # llama.cpp bindings
├── scripts/            # Dev workflow scripts
└── test/               # Widget tests

web_demo/
├── app.py              # Gradio application
├── requirements.txt
└── Dockerfile

research/
├── eval/               # Monte Carlo harness
└── papers/             # Paper outlines

spike/
├── artifacts/          # 16 synthetic documents
├── scripts/            # Spike experiment runners
└── docs/               # Findings reports
```

## Performance Characteristics

| Component | Latency | Notes |
|-----------|---------|-------|
| Blur detection | ~50ms | OpenCV on CPU |
| ML Kit OCR | ~100ms/doc | On-device, parallel |
| LLM inference | 11.9s | Gemma 4 E2B, Metal GPU |
| JSON parsing | <10ms | Retry adds ~50ms if needed |
| **Total** | **15.3s** | 4 documents + notice |

Memory: ~3.5GB peak (model + buffers + app)

## Security Considerations

- No network requests during document processing
- Model downloaded over HTTPS, verified by checksum
- No analytics or telemetry in production
- Eval mode only available in debug builds

## Future Work

- Fine-tuning on civic document corpus
- Core ML conversion for faster inference
- Android support (NNAPI/GPU delegation)
- Additional document types (housing, healthcare)
```

---

## Friday: Paper Outlines + Final Polish

### Morning (3 hours)
**Create `research/papers/nlp_ai/outline.md`**

```markdown
# On-Device Multimodal LLM Performance for Civic Document Understanding

## Target venue
CHI, EMNLP, or ACL findings track

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

## Current status
- Spike data: complete (Days 1-3)
- On-device Monte Carlo: in progress (Week 3)
- Token budget ablation: in progress (Week 3)
```

**Create `research/papers/civic_tech/outline.md`**

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

## Current status
- System implementation: complete (Weeks 1-2)
- Demo polish: in progress (Week 3)
- Evaluation: pending Monte Carlo results (Week 3)
```

### Afternoon (2 hours)
**Create `spike/README.md`**

Summarize the spike methodology and link to findings:

```markdown
# CivicLens Feasibility Spike

## Overview

Five-day structured feasibility study (March 2026) to determine whether 
Gemma 4 could reliably handle civic documents before building product code.

## Methodology

- 16 synthetic civic documents covering SNAP and BPS scenarios
- Clean PDFs + degraded phone-photo versions
- Formal ground truth for all extractable fields
- Pass/fail thresholds defined before experiments
- 100+ inference runs across E4B (via Ollama) and E2B (on device)

## Key Findings

| Capability | Result | Threshold | Status |
|------------|--------|-----------|--------|
| Document classification | 100% | 95% | PASS |
| BPS category mapping | 85.9% | 80% | PASS |
| SNAP category mapping | 66.7% | 70% | FAIL (proceed with caveats) |
| Critical safety checks | 0% FP | 0% FP | PASS |
| Field extraction (clean) | ~60% | 70% | FAIL (mitigated in UX) |
| Field extraction (degraded) | ~40% | 50% | FAIL (mitigated in UX) |
| Abstention on blurry images | 0% | 80% | FAIL (blur detection added) |

## Failure Modes Identified

1. **Column confusion** — Pay stubs with adjacent current/YTD columns
2. **Name confabulation** — Similar names on different documents
3. **Date misattribution** — Deadlines vs document dates

## Decision

PROCEED with known constraints. Document classification and category mapping 
are reliable enough for the core use case. Field extraction limitations 
addressed through human-in-loop UX design.

## Files

- `artifacts/` — 16 synthetic documents (clean + degraded)
- `docs/day1_findings.docx` — Classification experiments
- `docs/day2_findings.md` — Category mapping
- `docs/day3_findings.md` — Field extraction, safety checks
- `docs/day5_decision_memo.md` — Go/no-go decision
```

**Final verification:**
- [ ] Web demo feature parity complete
- [ ] HF Spaces keep-warm configured
- [ ] README.md complete
- [ ] ARCHITECTURE.md explains all decisions
- [ ] Both paper outlines committed
- [ ] Repo structure matches plan

---

## Acceptance Criteria

- [ ] Web demo feature parity with mobile (Track A deadline banner, Track B duplicate warning, no technical labels)
- [ ] HF Spaces keep-warm ping working
- [ ] README.md complete and accurate
- [ ] ARCHITECTURE.md explains all major technical decisions
- [ ] `spike/README.md` explains spike methodology and links to findings
- [ ] Both paper outlines committed to `research/papers/`
- [ ] Repo structure matches the plan

---

## Integration Points

| Handoff | To | When | What |
|---------|-----|------|------|
| Resident-friendly strings | From Agent 1 | Monday | LabelFormatter mapping table |
| Demo screenshots | From Agent 4 | Thursday | For README and papers |
| Architecture diagram | To Agent 4 | Wednesday | For video privacy section |
| Repo structure | All agents | Friday | Foundation for remaining work |

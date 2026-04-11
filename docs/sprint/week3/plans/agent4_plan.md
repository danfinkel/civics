# Agent 4 — Week 3 Plan: Video Script, Demo Recording, Kaggle Writeup Draft

**Week:** April 14–18, 2026  
**Owns:** Video production, `docs/video/`, `docs/kaggle_writeup_draft.md`  
**Goal:** Recorded video uploaded to YouTube by Friday. Kaggle writeup draft complete enough that Week 4 is editing, not writing.

---

## Monday: Final Video Script + Recording Prep

### Morning (2 hours)
**Review and finalize video script**

The video must be under 3 minutes. Every second allocated:

| Time | Section | Content |
|------|---------|---------|
| 0:00–0:25 | Problem | RMV story, no product shown |
| 0:25–0:40 | Approach | Spike methodology, brief |
| 0:40–1:45 | Demo Track A | D01/D03 flow, screen recording |
| 1:45–2:20 | Demo Track B | B4 duplicate category |
| 2:20–2:45 | Privacy | Architecture diagram |
| 2:45–3:00 | Close | Tagline, URLs |

**Script — Problem (0:00–0:25):**

> "A few years ago I drove to the RMV to upgrade my license to a Real ID. I brought what I thought were the right documents. I was turned away because my W-2 didn't have my Social Security number on it. I drove home, found the right document, drove back. The requirement existed — it just wasn't communicated clearly, and I had no way to check my specific documents against it before I went."

> "That same problem plays out every day for families navigating SNAP recertification, school enrollment, housing applications. The documents they need exist. The requirements are published. The gap is knowing whether what you have is what is needed — before you show up somewhere and find out it isn't."

**Script — Approach (0:25–0:40):**

> "Before building anything, we spent a week rigorously testing whether Gemma 4 could reliably handle real civic documents — government notices, pay stubs, leases, birth certificates, photographed on a phone. We measured accuracy, failure modes, and what the model genuinely cannot do. Those findings shaped every decision in what we built."

**Script — Demo Track A (0:40–1:45):**

Scene 1 (~20s): Home screen → select "SNAP Benefits"

Scene 2 (~15s): Photograph D01 notice. Blur check passes. Notice slot filled.

Scene 3 (~15s): Photograph D03 pay stub. Slot filled.

Scene 4 (~5s): Tap "Analyze My Documents"

Scene 5 (~10s): Processing state — "Reading your notice... Analyzing your documents..."

Scene 6 (~20s): Results. Deadline banner: "Respond by April 15." Proof pack: earned income — D03 satisfies it. Action summary.

Voiceover: "The app reads the notice, identifies the deadline, checks the pay stub against the requirement, and tells the resident what to do — in plain language, in 15 seconds, without their documents ever leaving the phone."

**Script — Demo Track B (1:45–2:20):**

Scene 7 (~15s): Switch to "School Enrollment." Upload D12, D05, D14, D13.

Scene 8 (~20s): Results. Three requirements satisfied. Duplicate warning banner.

Voiceover: "This is the kind of thing a caseworker would catch at the enrollment office — after the family has already made the trip. CivicLens catches it at home."

**Script — Privacy (2:20–2:45):**

> "Every document is processed entirely on the device using Gemma 4 E2B. OCR runs locally. Inference runs locally. Nothing is uploaded. For a resident submitting a birth certificate and a state ID, that matters."

**Script — Close (2:45–3:00):**

> "CivicLens. The knowledgeable friend who checks your documents before you go."

> "Open source. On device. Built on Gemma 4."

### Afternoon (2 hours)
**Recording preparation checklist:**

- [ ] iPhone 16 charged to >80%
- [ ] Download model to avoid showing download screen
- [ ] Set phone to Do Not Disturb
- [ ] Turn off battery percentage display
- [ ] Enable screen recording: Settings → Control Center → Screen Recording
- [ ] Verify test images in Photos app:
  - D01-degraded.jpg, D03-degraded.jpg (Track A)
  - D12-degraded.jpg, D05-degraded.jpg, D14-degraded.jpg, D13-degraded.jpg (Track B)
  - D01-blurry.jpg (optional, for A6)
- [ ] Good lighting setup for document photos
- [ ] Mac with QuickTime ready for backup capture
- [ ] Clear app state (fresh install or clear data)

---

## Tuesday: Screen Recording — Track A

### Morning (3 hours)
**Record Track A D01/D03 flow — 3 takes**

For each take:
1. Start screen recording on iPhone
2. Clear app state
3. Run through complete flow:
   - Home → SNAP Benefits
   - Upload D01 (notice)
   - Upload D03 (pay stub)
   - Tap Analyze
   - Show results screen for 5 seconds
4. Stop recording
5. Review for:
   - Smooth navigation
   - Clear document photos
   - No notifications/popups
   - Results screen fully visible

**Common issues to avoid:**
- Blur check failing (retake with better lighting)
- Slow model loading (ensure model pre-downloaded)
- Accidental taps (practice the flow first)

### Afternoon (2 hours)
**Select best take, note timestamps**

Review all 3 takes. Select the cleanest one. Note timestamps for:
- Scene 1 start: _
- Scene 2 start: _
- Scene 3 start: _
- Scene 4 start: _
- Scene 5 start: _
- Scene 6 start: _

Document any gaps that need voiceover coverage.

---

## Wednesday: Screen Recording — Track B

### Morning (3 hours)
**Record Track B B4 flow — 3 takes**

For each take:
1. Start screen recording
2. Clear app state
3. Run through complete flow:
   - Home → School Enrollment
   - Upload D12 (birth certificate)
   - Upload D05 (lease 1)
   - Upload D14 (lease 2 — same address)
   - Upload D13 (immunization record)
   - Tap Analyze
   - Show duplicate warning banner clearly
   - Show results for 5 seconds
4. Stop recording

**Critical shot:** The duplicate category warning must be clearly visible and readable.

### Afternoon (2 hours)
**Select best take, record architecture diagram**

Review Track B takes. Select cleanest.

**Record architecture diagram screen share:**
- Use ARCHITECTURE.md diagram from Agent 3
- 30 seconds, slow pan/zoom if needed
- Voiceover will cover privacy architecture

---

## Thursday: Video Editing + Kaggle Writeup Draft

### Morning (3 hours)
**Video editing**

Use iMovie, DaVinci Resolve, or CapCut:

1. Import Track A best take
2. Import Track B best take
3. Import architecture diagram recording
4. Create title card for opening (RMV story text)
5. Add transitions between scenes
6. Trim to ≤2:55 (5-second margin under 3:00)

**Audio:**
- Record voiceover separately for clarity
- Or use clean on-device audio if good quality
- Add background music at low volume (optional)

**Export settings:**
- Resolution: 1080p minimum
- Frame rate: 30fps
- Format: MP4 or MOV

Upload to YouTube as **Unlisted** for review.

### Afternoon (2 hours)
**Kaggle writeup — Sections 1-3 (650 words)**

Create `docs/kaggle_writeup_draft.md`:

```markdown
# CivicLens: Privacy-First Civic Document Intelligence with On-Device Gemma 4

## Subtitle
Helping residents navigate SNAP benefits and school enrollment using 
local multimodal AI — no documents leave the device.

## 1. The Problem (150 words)

Administrative burden in government service delivery is not distributed 
equally. Low-income residents navigating SNAP recertification, school 
enrollment, and housing applications face a document maze: requirements 
exist, notices are sent, but knowing whether your specific documents 
satisfy those requirements — before you show up somewhere and are turned 
away — remains a gap.

I experienced this personally at the RMV. I brought what I thought were 
the right documents for a Real ID. I was wrong. The requirement existed; 
I just had no way to verify my specific documents against it beforehand. 
That same gap affects families every day.

CivicLens is the knowledgeable friend who checks your documents before 
you go.

## 2. Why On-Device Gemma 4 (150 words)

Privacy is not a feature for civic documents — it is a requirement. 
Birth certificates, state IDs, pay stubs, and lease agreements are 
sensitive documents. Uploading them to a cloud API creates a liability 
that many residents cannot accept.

Gemma 4 E2B (2 billion active parameters) fits this need. It runs on 
consumer mobile hardware with acceptable latency. Its multimodal 
capability handles phone photographs of documents. Its Apache 2.0 
license allows deployment without licensing constraints.

The specific intersection matters: a model capable enough for document 
understanding, small enough for mobile, and free enough to deploy 
at scale.

## 3. Evidence-Driven Development: The Feasibility Spike (350 words)

Before writing product code, we ran a five-day structured feasibility 
spike. This is the differentiator.

**Methodology:**
- 16 synthetic civic documents (SNAP notices, pay stubs, leases, birth 
  certificates, immunization records)
- Clean PDFs + degraded phone-photo versions
- Formal ground truth for all extractable fields
- Pass/fail thresholds defined before experiments
- 100+ inference runs

**Key findings:**

| Capability | Result | Threshold | Status |
|------------|--------|-----------|--------|
| Document classification | 100% | 95% | PASS |
| BPS category mapping | 85.9% | 80% | PASS |
| SNAP category mapping | 66.7% | 70% | FAIL* |
| Critical safety checks | 0% FP | 0% FP | PASS |
| Field extraction | ~40-60% | 70% | FAIL* |

*Proceed with known constraints

**What worked:** Classification and category mapping are reliable 
enough for the core use case. Safety checks (the things that must 
never have false positives) passed completely.

**What didn't:** Field-level extraction has high hallucination rates 
on complex tabular layouts (pay stubs with adjacent current/YTD columns). 
The model cannot self-report illegibility on blurry images.

**How failure modes became design constraints:**
- Field extraction limitations → Human review UX (never auto-approve)
- Blurry image abstention failure → Blur detection preprocessing
- Missing-item detection gaps → Action summary as primary output

**Intellectual honesty moment:** We found a scorer bug mid-spike that 
inflated accuracy numbers. We fixed it and reported true results. The 
spike is only valuable if the findings are real.

The decision: PROCEED with known constraints. Build a system that 
works around model limitations rather than pretending they don't exist.
```

---

## Friday: Complete Writeup + Final Video

### Morning (3 hours)
**Kaggle writeup — Sections 4-6 (750 words)**

Continue `docs/kaggle_writeup_draft.md`:

```markdown
## 4. Architecture (250 words)

CivicLens uses a privacy-first on-device pipeline:

**OCR (391ms):** ML Kit Text Recognition runs locally on the device, 
extracting text from document photographs.

**LLM Inference (11.9s):** Gemma 4 E2B via llama.cpp with Metal GPU 
acceleration. The 2.9GB model runs entirely on-device. Documents never 
leave the phone.

**JSON Parsing:** Structured output with retry logic for edge cases 
(markdown fences, partial responses).

**Human-in-Loop Design:** The app never auto-approves documents. It 
presents reasoning and lets the resident decide. This is a civic design 
principle, not a technical fallback.

**Key technical stories:**
- FFI struct debugging: Dart-to-native bindings required ABI alignment 
  patches for stable initialization
- Gemma chat template: The model requires `<start_of_turn>user`/`model` 
  markers — without them, output is garbled
- Blur detection: Added after spike finding A6 showed the model cannot 
  self-report illegibility

**HF Spaces Web Demo:** For accessibility, a cloud fallback using the 
same pipeline logic runs on Hugging Face Spaces.

## 5. Results and Known Limitations (250 words)

**What works in production:**
- Document classification: 100% accuracy
- Category mapping: 85.9% (BPS), 66.7% (SNAP)
- JSON reliability: >95% parse success with retry
- End-to-end latency: 15.3 seconds for 4 documents

**Known limitations and mitigations:**

Field extraction hallucination (~40% on complex layouts) is mitigated 
by human review UX. The app presents extracted fields as "appears to 
show" rather than fact, and the action summary (not raw extraction) 
is the primary output.

Blurry image abstention failure is mitigated by blur detection 
preprocessing. Users see a warning and can retake or proceed with 
caution.

Missing-item detection (50-67% recall) is mitigated by action summary 
guidance. The app tells the resident what to look for, even if it 
cannot confirm absence.

We are honest about limitations because residents deserve to know 
what the app can and cannot do.

## 6. Impact and Next Steps (150 words)

CivicLens demonstrates that on-device AI can address real civic 
problems while preserving privacy. The resident story matters: a 
parent checking documents at home before a school enrollment trip, 
a SNAP recipient verifying their packet before the deadline.

Privacy is equity. Cloud-based solutions exclude residents who 
cannot risk document exposure. On-device inference is a requirement, 
not a feature.

**Research in progress:**
- NLP/AI paper: Systematic evaluation of Gemma 4 for civic document 
  understanding with Monte Carlo experiments
- Civic tech paper: Design principles for privacy-first government 
  service navigation tools

**Post-hackathon:** Fine-tuning on civic document corpus, Android 
support, additional document types (housing, healthcare).

CivicLens is open source. The methodology is replicable. The code 
is available. The goal is to make government service navigation 
work for everyone.
```

Word count check: Target ~1,400 words (under 1,500 limit).

### Afternoon (2 hours)
**Final video polish + cover image**

**Final video edits:**
- [ ] Voiceover synchronized with screen recording
- [ ] RMV story text on screen for opening
- [ ] Architecture diagram visible in privacy section
- [ ] Final cut ≤2:55
- [ ] Export 1080p

**Create cover image:**
- Dimensions: 1280×720 (YouTube thumbnail)
- Content: App screenshot + CivicLens logo/text
- Style: Clean, readable at small size

**Upload and share:**
- [ ] Upload to YouTube as Unlisted
- [ ] Share link with team for review
- [ ] Prepare to make Public after feedback

---

## Acceptance Criteria

- [ ] Video recorded, edited to ≤3:00, uploaded to YouTube (unlisted for review)
- [ ] Both Track A (D01/D03) and Track B (B4) scenarios captured cleanly
- [ ] RMV story in the opening 25 seconds
- [ ] Privacy architecture diagram visible in video
- [ ] Kaggle writeup draft complete at ~1,400 words
- [ ] Writeup covers all 6 sections with correct word budgets
- [ ] Cover image created for Kaggle submission (1280×720)

---

## Integration Points

| Handoff | From | When | What |
|---------|------|------|------|
| Demo-ready app | Agent 1 | Friday | For video recording |
| Architecture diagram | Agent 3 | Wednesday | For video privacy section |
| Monte Carlo results | Agent 2 | Thursday | Accuracy numbers for writeup |
| Demo screenshots | To Agent 3 | Thursday | For README |
| Video draft link | To all | Friday | For review before public |

---

## Recording Checklist (Print and Use)

**Before each recording session:**
- [ ] iPhone charged >80%
- [ ] Model pre-downloaded (no download screen)
- [ ] Do Not Disturb enabled
- [ ] Battery percentage hidden
- [ ] Test images in Photos app
- [ ] Good lighting
- [ ] Practice run completed

**Track A flow:**
- [ ] Home → SNAP Benefits
- [ ] Upload D01-degraded.jpg
- [ ] Upload D03-degraded.jpg
- [ ] Tap Analyze
- [ ] Results: deadline banner visible
- [ ] Results: earned income satisfied

**Track B flow:**
- [ ] Home → School Enrollment
- [ ] Upload D12-degraded.jpg
- [ ] Upload D05-degraded.jpg
- [ ] Upload D14-degraded.jpg
- [ ] Upload D13-degraded.jpg
- [ ] Tap Analyze
- [ ] Results: duplicate warning banner prominent

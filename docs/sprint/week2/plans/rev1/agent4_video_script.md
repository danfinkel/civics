# Agent 4 — Week 2 Work Plan
## Video Script + Demo Scenarios

**Agent:** Agent 4 (Design System + Video Production)  
**Sprint:** Week 2 (April 14–18, 2026)  
**Goal:** 3-minute video script drafted. Demo scenarios B1 and B4 prepared with real synthetic documents.

---

## Dependencies

- **Agents 1-3:** Working demo needed by Thursday for screen recording
- **Spike artifacts:** Document images from `/spike/artifacts/`

---

## Deliverables

### 1. Video Script (3 Minutes)

**File:** `docs/video/script.md`

**Timing Breakdown:**

| Time | Section | Visual | Audio Script |
|------|---------|--------|--------------|
| 0:00–0:30 | The Problem | Text/animation only | "Every year, families applying for SNAP benefits or enrolling children in school face the same challenge: gathering the right documents, by the right deadline, in the right combination. Miss a requirement and you start over. The instructions exist — but understanding whether what you have is what is needed requires expertise most families don't have access to." |
| 0:30–1:00 | Our Approach | Spike methodology diagram | "Before building, we spent a week rigorously testing whether Gemma 4 could reliably handle civic documents — pay stubs, leases, government notices, birth certificates. We ran over 100 experiments, measured failure modes, and designed the product around what we learned." |
| 1:00–2:15 | Demo (Track B) | Screen recording, real app | "Here's how it works. A family uploads their documents: birth certificate, lease agreement, utility bill, immunization record. CivicLens processes everything on the device using Gemma 4. In under a minute, it shows all four requirements satisfied. Now watch what happens when something's wrong. Swap the utility bill for a second lease — CivicLens flags the duplicate category violation. Two leases count as one proof. The family knows to bring a different document." |
| 2:15–2:45 | Privacy Architecture | Architecture diagram | "Every document is processed entirely on device using Gemma 4 E2B. Nothing is uploaded. For a resident submitting a birth certificate and a state ID, that matters." |
| 2:45–3:00 | Call to Action | App on phone | "CivicLens. Documents stay on your phone. Help gets to the people who need it." |

**Script Notes:**
- Read aloud and time yourself — should be 2:45–3:00
- Plain language, no jargon
- Emphasize "on device" and privacy

---

### 2. Demo Scenarios Prepared

**File:** `docs/video/scenarios.md`

**Scenario B1 — Complete Valid Packet (Happy Path)**

Documents to use:
1. D12 (birth certificate) — Proof of Age
2. D05 (lease agreement) — Residency Proof 1
3. D06 (utility bill) — Residency Proof 2
4. D13 (immunization record) — Immunization

Expected output:
```json
{
  "requirements": [
    {"requirement": "Proof of Age", "status": "satisfied"},
    {"requirement": "Residency Proof 1", "status": "satisfied"},
    {"requirement": "Residency Proof 2", "status": "satisfied"},
    {"requirement": "Immunization Record", "status": "satisfied"}
  ],
  "duplicate_category_flag": false,
  "family_summary": "Your registration packet looks complete!"
}
```

Recording steps:
1. Open CivicLens app
2. Select "School Enrollment"
3. Upload D12 → "Proof of Age" slot
4. Upload D05 → "Residency Proof 1" slot
5. Upload D06 → "Residency Proof 2" slot
6. Upload D13 → "Immunization Record" slot
7. Tap "Check My Packet"
8. Show loading state
9. Show results: all 4 satisfied
10. Highlight family summary

**Scenario B4 — Duplicate Category Warning**

Documents to use:
1. D12 (birth certificate) — Proof of Age
2. D05 (lease agreement) — Residency Proof 1
3. D14 (second lease) — Residency Proof 2 ← DUPLICATE
4. D13 (immunization record) — Immunization

Expected output:
```json
{
  "requirements": [
    {"requirement": "Proof of Age", "status": "satisfied"},
    {"requirement": "Residency Proof 1", "status": "satisfied"},
    {"requirement": "Residency Proof 2", "status": "satisfied"},
    {"requirement": "Immunization Record", "status": "satisfied"}
  ],
  "duplicate_category_flag": true,
  "duplicate_category_explanation": "Two documents from the same category...",
  "family_summary": "You need a second document from a different category."
}
```

Recording steps:
1. Start from B1 results
2. Tap "Start Over"
3. Re-upload D12, D05, D13
4. Upload D14 (second lease) instead of D06
5. Tap "Check My Packet"
6. Show results: all satisfied BUT warning banner appears
7. Highlight duplicate category warning

---

### 3. Screen Recording Setup Guide

**File:** `docs/video/recording_setup.md`

**Mobile Recording (Preferred):**

iOS:
1. Settings → Control Center → Add "Screen Recording"
2. Open CivicLens app
3. Swipe down from top-right → tap Screen Recording
4. Walk through scenario
5. Stop recording (tap red status bar)
6. Video saves to Photos

Android:
1. Swipe down twice from top
2. Tap "Screen Record"
3. Walk through scenario
4. Stop recording
5. Video saves to Gallery

**Simulator Recording (Backup):**

macOS:
```bash
# iOS Simulator
xcrun simctl io booted recordVideo scenario_b1.mov

# Stop with Ctrl+C
```

**Post-Processing:**
- Trim to remove setup/teardown
- Add captions if audio is unclear
- Target: 75 seconds for B1, 45 seconds for B4

---

### 4. Presentation Slides (Optional)

If video needs title cards or transitions, create slide specs:

**File:** `docs/video/slides.md`

**Slide 1: Title Card**
- Background: Dark navy (#002444)
- Text: "CivicLens" (white, 48pt)
- Subtext: "Privacy-First Civic Document Intelligence"
- Duration: 3 seconds

**Slide 2: Architecture Diagram**
- Phone → Gemma 4 E2B → Results
- No cloud icon
- Text: "Documents never leave your device"
- Duration: 15 seconds (during privacy section)

---

## File Structure

```
docs/
└── video/
    ├── script.md              # 3-minute script
    ├── scenarios.md           # B1 and B4 walkthroughs
    ├── recording_setup.md     # Technical guide
    └── slides.md              # Optional presentation slides
```

---

## Daily Checkpoints

| Day | Target |
|-----|--------|
| Monday | Script draft complete, timed reading |
| Tuesday | Scenarios documented, document files located |
| Wednesday | Recording setup tested |
| Thursday | Screen recording with working demo |
| Friday | Raw footage complete, handoff to editing (Week 3) |

---

## Acceptance Criteria

- [ ] 3-minute script drafted and timed
- [ ] B1 scenario documented with expected outputs
- [ ] B4 scenario documented with expected outputs
- [ ] Recording setup guide complete
- [ ] Raw screen recordings captured (both scenarios)
- [ ] Footage handed off to Week 3 for editing

---

## Notes

- Script should be plain language — readable by a 10-year-old
- Practice reading aloud before recording
- Have backup documents ready if spike artifacts don't work
- Coordinate with Agent 1 on Thursday for recording session
- Week 3 will handle editing, music, and final export

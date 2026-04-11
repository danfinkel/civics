# Agent 1 — Friday Mission: Demo Ready

**Date:** Friday, April 10, 2026  
**Goal:** Working B1 demo on physical iPhone, ready for recording  
**Success Criteria:** Resident can upload 4 docs, see "4 satisfied" result

---

## Morning: Integration (9am–12pm)

### Step 1: Receive Handoff from Agent 2 (1 hour)

**Get from Agent 2:**
- Working `InferenceService.analyzeTrackBWithOcr()`
- Performance numbers (OCR time, LLM time)
- Any prompt tuning notes
- Error handling behavior

**Verify on your device:**
```bash
flutter test integration_test/b1_pipeline_test.dart -d <your-iphone-id>
```

**Must pass before proceeding.**

---

### Step 2: UI Integration (2 hours)

**Update Track B screen:**

```dart
// In TrackBController
Future<void> analyzeDocuments() async {
  setState(ViewState.loading);
  
  // Show progress: "Reading documents..."
  updateProgress("Reading document 1 of 4...");
  
  final service = InferenceService();
  await service.initialize();
  
  final result = await service.analyzeTrackBWithOcr(
    documents: _documents.map((d) => d.imageBytes).toList(),
  );
  
  if (result.isSuccess) {
    _result = result.data;
    setState(ViewState.success);
  } else {
    _error = result.errorMessage;
    setState(ViewState.error);
  }
}
```

**UI states:**
| State | Message | Progress |
|-------|---------|----------|
| OCR | "Reading document X of 4..." | 0-30% |
| LLM | "Analyzing documents..." | 30-100% |
| Success | "Analysis complete" | 100% |
| Error | Specific error message | - |

---

## Afternoon: Testing + Demo Prep (1pm–5pm)

### Step 3: B1 Scenario Test (1 hour)

**Manual test:**
1. Launch app on iPhone
2. Select "School Enrollment"
3. Upload D12 → "Proof of Age"
4. Upload D05 → "Residency Proof 1"
5. Upload D06 → "Residency Proof 2"
6. Upload D13 → "Immunization Record"
7. Tap "Check My Packet"
8. **Verify:** Results show "4 satisfied"

**Time the full flow:**
- Document upload: ___s
- OCR: ___s
- LLM inference: ___s
- Results display: ___s
- **Total: ___s**

---

### Step 4: Error Scenarios (30 min)

**Test each:**
- [ ] No documents → "Add at least one document"
- [ ] 1 document only → Analysis runs, shows missing items
- [ ] Blurry document → OCR warning, retake prompt
- [ ] Timeout → "Taking longer than expected" dialog

---

### Step 5: Demo Polish (1 hour)

**For Agent 4's recording:**

1. **Clean data:** Reset app, fresh install
2. **Pre-position documents:** Have D12, D05, D06, D13 ready
3. **Test lighting:** Ensure document photos are clear
4. **Verify flow:** Run B1 twice, confirm consistent

**Demo script:**
```
1. "Here's CivicLens helping a family prepare for school enrollment."
2. Upload 4 documents (narrate each)
3. "Now the app analyzes everything on the device — nothing is uploaded."
4. Show loading state
5. "Four requirements satisfied. The family knows they're ready."
6. Show action summary
```

---

### Step 6: Handoff to Agent 4 (30 min)

**Deliver:**
- Working app on iPhone
- 4 test documents ready
- Expected demo flow
- Timing (how long each step takes)

**Coordinate recording:**
- Afternoon or evening recording session
- Quiet space for narration
- Screen recording + voiceover

---

## Success Criteria (EOD Friday)

### Green (Demo Ready)
- [ ] B1 scenario works on physical iPhone
- [ ] UI shows progress during OCR + LLM
- [ ] Results display correctly
- [ ] Error states handled
- [ ] App handed off to Agent 4 for recording

### Yellow (Demo with Workarounds)
- [ ] B1 works but slow (>120s)
- [ ] OR: Minor UI glitches
- [ ] Action: Demo anyway, document issues

### Red (Blocked)
- [ ] B1 fails on device
- [ ] OR: Agent 2 handoff didn't work
- [ ] Action: Escalate immediately

---

## Time Budget

| Task | Time | Drop Dead |
|------|------|-----------|
| Agent 2 handoff | 1h | 10am |
| UI integration | 2h | 12pm |
| **LUNCH** | | |
| B1 manual test | 1h | 2pm |
| Error scenarios | 30m | 2:30pm |
| Demo polish | 1h | 3:30pm |
| Agent 4 handoff | 30m | 4pm |
| Buffer | 1h | 5pm |

---

## Escalation Triggers

**Escalate immediately:**

| Problem | Info to Send |
|---------|--------------|
| Agent 2 code doesn't work on your device | Error message, your iPhone model |
| UI crashes during test | Crash log, which screen |
| Results don't display | Screenshot, expected vs actual |
| B1 fails consistently | Step that failed, error message |

---

## Key Reminder

**Agent 2 did the hard work.** Model runs on device, inference works.

Your job: Make it usable and demo-ready.

Focus on:
- Clear progress indicators (OCR → LLM)
- Clean results display
- Reliable B1 flow

---

## Friday Definition of Done

**For Agent 1:**
- [ ] B1 works on your iPhone
- [ ] UI polished
- [ ] Handed off to Agent 4

**For CivicLens Week 2:**
- [ ] Demo ready for recording
- [ ] Privacy-first architecture proven
- [ ] Ready for Week 3 polish

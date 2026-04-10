# Agent 2 — Friday Mission: Full Pipeline on Device

**Date:** Friday, April 10, 2026  
**Goal:** B1 scenario (4 docs → OCR → LLM → JSON) works end-to-end on iPhone  
**Success Criteria:** "4 satisfied" result from real documents, total time measured

---

## Morning: OCR + Pipeline Test (9am–12pm)

### Step 1: OCR on Device (1 hour)

**Test file:** `integration_test/ocr_device_test.dart`

```dart
test('OCR extracts text from D12', () async {
  final ocr = OcrService();
  final image = File('/path/to/D12.jpg').readAsBytesSync();
  final text = await ocr.extractText(image);
  
  print('Extracted: $text');
  expect(text, contains('Birth')); // or name, date, etc.
});
```

**Run:**
```bash
flutter test integration_test/ocr_device_test.dart -d <iphone-id>
```

**Verify:** OCR returns readable text (not garbage).

**If fails:**
- Check ML Kit initialization
- Try different document (D05, D06)
- **Escalate with sample output**

---

### Step 2: Full B1 Pipeline (2 hours)

**Documents needed:**
- D12 (birth certificate)
- D05 (lease agreement)
- D06 (utility bill)
- D13 (immunization record)

**Test:**
```bash
flutter test integration_test/b1_pipeline_test.dart -d <iphone-id>
```

**Expected flow:**
```
1. Load 4 document images
2. OCR each → extracted text
3. Build prompt with OCR text
4. LLM inference → raw response
5. Parse JSON → TrackBResult
6. Verify: 4 requirements satisfied
```

**Measure and record:**
| Metric | Time | Target |
|--------|------|--------|
| OCR (4 docs) | ___s | <30s |
| LLM inference | ___s | <90s |
| JSON parsing | ___s | <5s |
| **Total** | ___s | **<120s** |

---

## Afternoon: Polish + Handoff (1pm–5pm)

### Step 3: JSON Parsing Tuning (1 hour)

**If LLM returns malformed JSON:**

1. Check prompt in `inference_service.dart`
2. Add explicit JSON format instructions
3. Use `ResponseParser` retry wrapper
4. Test again

**Example prompt tuning:**
```
You are analyzing school enrollment documents.
Documents provided as OCR text below.
Return ONLY valid JSON. No markdown, no explanation.

{"requirements": [...], "family_summary": "..."}
```

---

### Step 4: Error Handling (1 hour)

**Add graceful failures:**
- OCR returns empty → "Could not read document"
- LLM timeout → "Analysis taking longer than expected"
- JSON parse fails → "Could not understand results"

**Test each error path once.**

---

### Step 5: Handoff to Agent 1 (1 hour)

**Deliver to Agent 1:**
1. Working `InferenceService.analyzeTrackBWithOcr()`
2. Performance numbers (OCR time, LLM time)
3. Any prompt tuning needed
4. Error handling behavior

**Verify together:**
- B1 scenario passes on Agent 1's device
- UI shows correct results
- Loading states work

---

## Success Criteria (EOD Friday)

### Green (Demo Ready)
- [ ] OCR works on device
- [ ] B1 pipeline returns "4 satisfied"
- [ ] Total time < 120 seconds
- [ ] JSON parsing reliable
- [ ] Handed off to Agent 1

### Yellow (Demo with Caveats)
- [ ] B1 works but >120s
- [ ] OR: JSON parsing needs retry sometimes
- [ ] Action: Document, demo anyway

### Red (Blocked)
- [ ] OCR fails on device
- [ ] OR: Pipeline crashes
- [ ] Action: Escalate immediately

---

## Time Budget

| Task | Time | Drop Dead |
|------|------|-----------|
| OCR test | 1h | 10am |
| B1 pipeline | 2h | 12pm |
| **LUNCH** | | |
| JSON tuning | 1h | 2pm |
| Error handling | 1h | 3pm |
| Handoff | 1h | 4pm |
| Buffer | 1h | 5pm |

---

## Escalation Triggers

**Escalate immediately:**

| Problem | Info to Send |
|---------|--------------|
| OCR returns garbage | Sample document, OCR output |
| Pipeline crashes | Crash log, which step failed |
| LLM hangs >5min | Prompt used, document count |
| JSON always malformed | Sample LLM output |

**How to escalate:**
1. Try one fix (prompt tuning, different doc)
2. If still broken after 30 min → escalate
3. Send: exact error, what you tried, logs

---

## Key Reminder

**The hard part is done.** Model loads, inference works, returns correct answers.

Today is about plumbing: connecting OCR → LLM → JSON.

Lower risk than yesterday. Focus on measurement and reliability.

---

## Friday Definition of Done

**For Agent 2:**
- [ ] B1 works on device
- [ ] Performance measured
- [ ] Handed off to Agent 1

**For CivicLens Week 2:**
- [ ] On-device inference proven
- [ ] Privacy promise kept
- [ ] Demo ready for recording

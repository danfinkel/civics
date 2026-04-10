# CivicLens Week 2 — Friday Morning Status

**Date:** Friday, April 10, 2026  
**Reporter:** Agent 2 (On-Device Inference)  
**Status:** 🟡 ON TRACK — Core pipeline ready for device testing

---

## Executive Summary

On-device Gemma 4 inference is **proven working** on iPhone. Thursday's breakthrough eliminated the three hardest risks (model loading, library compatibility, FFI struct alignment). Friday's work is lower-risk pipeline integration: connecting OCR → LLM → JSON.

**Demo readiness:** If B1 pipeline passes this morning, we have a working end-to-end privacy-first document analyzer.

---

## Thursday Achievement: On-Device Inference Proven

| Component | Status | Evidence |
|-----------|--------|----------|
| Model download (WiFi) | ✅ | 2.9GB transferred via local HTTP |
| Library loading | ✅ | Custom combined dylib, code-signed |
| Model loading (Gemma 4 E2B) | ✅ | Loads with Metal GPU acceleration |
| Inference | ✅ | Returns "4" for B1 prompt (correct answer) |
| App stability | ✅ | No crashes, clean lifecycle |

### Three Hard Problems Solved

1. **API Version Mismatch** — llama_cpp_dart 0.0.9 had outdated FFI bindings causing silent memory corruption. Fixed by upgrading to 0.2.2 + patching 3 struct fields.

2. **Gemma 4 Not Recognized** — Model architecture `gemma4` added to llama.cpp in April 2026. Fixed by rebuilding dylib from commit `d9a12c82f`.

3. **C Struct ABI Break** — Three llama.cpp structs gained new fields between Dec 2025 and April 2026. Fixed by patching Dart FFI definitions to match native layout.

---

## Friday Plan: Full Pipeline on Device

### Morning (9am–12pm): OCR + Pipeline Test

**Test files created:**
- `integration_test/ocr_device_test.dart` — OCR on 4 B1 documents
- `integration_test/b1_pipeline_test.dart` — Full OCR → LLM → JSON pipeline
- `integration_test/fixtures/` — D05, D06, D12, D13 JPGs (converted from PDFs)

**Documents:**
- D12: Birth certificate (Proof of Age)
- D05: Lease agreement (Residency Proof 1)
- D06: Utility bill (Residency Proof 2)
- D13: Immunization record

**Run commands:**
```bash
# Step 1: OCR test (1 hour)
flutter test integration_test/ocr_device_test.dart -d <iphone-id>

# Step 2: B1 pipeline (2 hours)
flutter test integration_test/b1_pipeline_test.dart -d <iphone-id>
```

**Success criteria:**
- OCR extracts readable text from all 4 documents
- Pipeline returns "4 satisfied" requirements
- Total time < 120 seconds (OCR <30s, LLM <90s)

### Afternoon (1pm–5pm): Polish + Handoff

| Time | Task | Output |
|------|------|--------|
| 1–2pm | JSON parsing tuning | Reliable TrackBResult parsing |
| 2–3pm | Error handling | Graceful failures for OCR/LLM errors |
| 3–4pm | Handoff to Agent 1 | Working InferenceService, performance numbers |
| 4–5pm | Buffer | Demo verification on Agent 1's device |

---

## Risk Assessment

| Risk | Status | Mitigation |
|------|--------|------------|
| OCR fails on device | 🟡 Medium | ML Kit proven on iOS; test this morning |
| Pipeline too slow (>120s) | 🟡 Medium | Target is 30s OCR + 90s LLM; measure first |
| JSON parsing unreliable | 🟡 Medium | Prompt tuning + retry wrapper ready |
| Model crashes | 🟢 Low | Fixed Thursday; vendored patches in git |

**Escalation triggers:**
- OCR returns garbage → Send sample document + output
- Pipeline crashes → Send crash log + step that failed
- LLM hangs >5min → Send prompt + document count

---

## Files Changed This Session

### New
- `integration_test/ocr_device_test.dart`
- `integration_test/b1_pipeline_test.dart`
- `integration_test/fixtures/D{05,06,12,13}.jpg`
- `docs/sprint/week2_reports/rev2/friday_morning_status.md` (this file)

### Modified
- `pubspec.yaml` — Added test fixtures to assets
- `lib/core/models/track_b_result.dart` — Added `satisfiedCount` getter

---

## Performance Targets

| Metric | Target | Measured | Status |
|--------|--------|----------|--------|
| Model load | ~30s | TBD | ⏳ Pending |
| OCR (4 docs) | <30s | TBD | ⏳ Pending |
| LLM inference | <90s | TBD | ⏳ Pending |
| **Total B1** | **<120s** | **TBD** | ⏳ **Pending** |

---

## Definition of Done (EOD Friday)

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

## Key Reminder

**The hard part is done.** Model loads, inference works, returns correct answers. Today is plumbing: connecting proven components (OCR → LLM → JSON).

Lower risk than Thursday. Focus on measurement and reliability.

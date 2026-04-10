# Agent 2 — Thursday Mission: Prove It Works on Device

**Date:** Thursday, April 9, 2026  
**Goal:** B1 scenario passes on physical iPhone  
**Success Criteria:** 4 documents → OCR → LLM → "4 satisfied" result

---

## Morning: Device Setup (9am–12pm)

### Step 1: Deploy Model to iPhone (30 min)

**Option A: Xcode Device Manager (Recommended)**
```bash
# 1. Open Xcode
# 2. Window > Devices and Simulators
# 3. Select your iPhone
# 4. Find CivicLens app, click gear icon > Download Container
# 5. In Finder, right-click .xcappdata > Show Package Contents
# 6. Copy gemma-4-E2B-it-Q4_K_M.gguf to Documents/models/
# 7. In Xcode, Upload Container
```

**Option B: Bundle in App (Slower but reliable)**
```yaml
# pubspec.yaml
flutter:
  assets:
    - assets/models/gemma-4-E2B-it-Q4_K_M.gguf
```

**Verify:**
```dart
final path = await ModelManager.getModelPath();
final exists = File(path).existsSync();
print('Model exists: $exists, size: ${File(path).lengthSync()} bytes');
```

---

### Step 2: Basic Inference Test (1 hour)

**Run:**
```bash
flutter test integration_test/llama_test.dart -d <your-iphone-id>
```

**Expected output:**
```
00:00 +0: llama.cpp loads model
00:30 +1: llama.cpp responds to prompt
Response: "Hello! I'm Gemma, an AI assistant..."
```

**If fails:**
- Check model path in error
- Check iOS console for crash logs
- Verify iPhone has >3GB free RAM
- **Escalate with exact error message**

---

### Step 3: OCR Test (30 min)

**Test with D12 (birth certificate):**
```bash
flutter test integration_test/ocr_test.dart -d <your-iphone-id>
```

**Verify:** OCR extracts readable text (names, dates, etc.)

---

## Afternoon: Pipeline Test (1pm–5pm)

### Step 4: End-to-End B1 Scenario (2 hours)

**Documents needed:**
- D12 (birth certificate) — Proof of Age
- D05 (lease agreement) — Residency 1
- D06 (utility bill) — Residency 2  
- D13 (immunization record) — Immunization

**Test:**
```bash
flutter test integration_test/pipeline_test.dart -d <your-iphone-id>
```

**Expected result:**
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

**Measure and record:**
- Model load time: ___ seconds
- OCR time per document: ___ seconds
- LLM inference time: ___ seconds
- Total time: ___ seconds

---

### Step 5: Handoff to Agent 1 (1 hour)

**If B1 passes:**
1. Document exact steps for Agent 1
2. Provide model path configuration
3. Confirm API: `service.analyzeTrackBWithOcr(documents: images)`
4. Share performance numbers

**If B1 fails:**
1. Document what failed (OCR? LLM? Parser?)
2. Provide error logs
3. Recommend: fix, workaround, or escalate

---

## Success Criteria (EOD Thursday)

### Green (Proceed to Friday Demo)
- [ ] Model loads on iPhone
- [ ] OCR extracts text from documents
- [ ] B1 scenario returns "4 satisfied"
- [ ] Total time < 120 seconds

### Yellow (Proceed with Caveats)
- [ ] B1 works but >120 seconds
- [ ] OR: Works but memory warnings
- [ ] Action: Document, optimize Friday

### Red (Escalate)
- [ ] Model won't load
- [ ] OCR returns garbage
- [ ] LLM crashes or hangs
- [ ] Action: Escalate with logs, decide cloud vs. delay

---

## Time Budget

| Task | Time | Drop Dead |
|------|------|-----------|
| Model deploy | 30m | 10am |
| Basic inference | 1h | 11am |
| OCR test | 30m | 12pm |
| **LUNCH** | | |
| B1 pipeline | 2h | 3pm |
| Debug/fix | 1h | 4pm |
| Handoff | 1h | 5pm |

**If behind at 3pm:** Skip OCR test, go straight to B1. OCR already validated in spike.

---

## Escalation Triggers

**Stop and escalate immediately:**

| Problem | What to Send |
|---------|--------------|
| Model crashes on load | iPhone model, iOS version, crash log from Xcode |
| Out of memory | Available RAM (Settings > General > About), model size |
| Inference hangs >5min | Screenshot of Xcode console, last log line |
| OCR returns empty | Sample document name, OCR confidence score |
| Build won't run on device | `flutter doctor -v` output, Xcode version |

**How to escalate:**
1. Try one fix attempt (Google error, check paths)
2. If still broken after 30 min: escalate
3. Send: exact error, what you tried, iPhone/iOS version

---

## Commands Reference

```bash
# Get iPhone device ID
flutter devices

# Run specific test
flutter test integration_test/llama_test.dart -d <device-id>

# Run with verbose logging
flutter test integration_test/pipeline_test.dart -d <device-id> --verbose

# Check iOS logs
flutter logs

# Build release version
flutter build ios --release
```

---

## Remember

- **B1 scenario is the goal** — everything else is secondary
- **Measure times** — we need real numbers for Friday
- **Document steps** — Agent 1 needs to reproduce
- **Escalate early** — don't spend 3 hours on same error
- **Privacy first** — no cloud calls, everything on device

**Today determines if Friday demo is on-device or not.**

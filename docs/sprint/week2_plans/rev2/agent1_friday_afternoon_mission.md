# Agent 1 — Friday Afternoon Mission: Demo Ready

**Date:** Friday, April 10, 2026  
**Status:** Agent 2 delivered working B1 pipeline — your turn to integrate and demo  
**Goal:** Working B1 demo on your iPhone, ready for Agent 4 recording

---

## What Agent 2 Delivered

**Working B1 pipeline:**
- OCR (4 docs): 391ms
- LLM inference: 11.9s
- **Total: 15.3s** (8x faster than target)
- Returns valid JSON with correct analysis

**Key files:**
- `mobile/lib/core/inference/inference_service.dart` — `analyzeTrackBWithOcr()`
- `mobile/lib/core/inference/llama_client.dart` — Model config (nCtx=4096, nBatch=2048)
- `mobile/ios/Frameworks/libllama.dylib` — Vendored library

**Model path (CRITICAL):**
- Agent 2's test uses: `Documents/gemma-4-E2B-it-Q4_K_M.gguf`
- Your `ModelManager` expects: `Documents/models/gemma-4-E2B-it-Q4_K_M.gguf`
- **Fix:** Align these paths (see Step 1 below)

---

## Step-by-Step Integration

### Step 1: Fix Model Path (15 min)

**Option A: Update ModelManager (Recommended)**
```dart
// In model_manager.dart
static const String modelFileName = 'gemma-4-E2B-it-Q4_K_M.gguf';

static Future<String> getModelPath() async {
  final docsDir = await getApplicationDocumentsDirectory();
  // Change from: return '${docsDir.path}/models/$modelFileName';
  // To:
  return '${docsDir.path}/$modelFileName';
}
```

**Option B: Move model file**
- Create `Documents/models/` directory
- Move/copy `gemma-4-E2B-it-Q4_K_M.gguf` there

**Verify path exists before running:**
```dart
final path = await ModelManager.getModelPath();
final exists = File(path).existsSync();
print('Model exists: $exists at $path');
```

---

### Step 2: Integrate Progress Callbacks (30 min)

Your UI already has progress indicators. Wire them to Agent 2's callbacks:

```dart
// In track_b_controller.dart
Future<void> analyzeDocuments() async {
  setState(ViewState.loading);
  
  final service = InferenceService();
  await service.initialize(
    onProgress: (p) => updateProgress('Loading model...', p * 0.3),
  );
  
  final result = await service.analyzeTrackBWithOcr(
    documents: _documents.map((d) => d.imageBytes).toList(),
    onOcrProgress: (index, total) {
      updateProgress(
        'Reading document ${index + 1} of $total...',
        0.3 + (index / total) * 0.2,  // 30-50%
      );
    },
    onLlmProgress: (p) {
      updateProgress(
        p < 0.8 ? 'Analyzing documents...' : 'Almost done...',
        0.5 + p * 0.5,  // 50-100%
      );
    },
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

---

### Step 3: Build and Install (30 min)

```bash
cd mobile

# Clean build
flutter clean
flutter pub get

# Build for iOS release
flutter build ios --release

# Install on your device
flutter install -d <your-iphone-id>

# Or use Xcode:
# Open ios/Runner.xcworkspace
# Select your device, Product > Archive > Distribute
```

**Expected:** App installs, launches without crash.

---

### Step 4: Test B1 Scenario (30 min)

**Documents needed:**
- D12 (birth certificate) — Proof of Age
- D05 (lease agreement) — Residency Proof 1
- D06 (utility bill) — Residency Proof 2
- D13 (immunization record) — Immunization

**Test steps:**
1. Launch app on your iPhone
2. Select "School Enrollment"
3. Upload D12 → "Proof of Age" slot
4. Upload D05 → "Residency Proof 1"
5. Upload D06 → "Residency Proof 2"
6. Upload D13 → "Immunization Record"
7. Tap "Check My Packet"
8. **Watch progress:** OCR → LLM → Results
9. **Verify:** "4 satisfied" or "3 satisfied" (depending on BPS requirements)

**Expected timing:**
- Progress bar moves: 0% → 30% (model load)
- "Reading document X of 4...": 30% → 50%
- "Analyzing documents...": 50% → 100%
- Results: ~15 seconds total

---

### Step 5: Error Handling Check (15 min)

**Test each:**
- [ ] No documents → "Add at least one document"
- [ ] 1 document only → Analysis runs, shows missing items
- [ ] Tap "Check My Packet" twice quickly → No crash
- [ ] Background app during analysis → Resumes correctly

---

### Step 6: Demo Polish (30 min)

**Prepare for Agent 4:**

1. **Clean install:**
   ```bash
   flutter install -d <device-id> --uninstall-first
   ```

2. **Pre-position documents:** Have D12, D05, D06, D13 ready to photo

3. **Test lighting:** Ensure document photos are clear (good OCR = good demo)

4. **Run B1 twice:** Confirm consistent results

5. **Document timing:**
   - Your measured OCR time: ___s
   - Your measured LLM time: ___s
   - Your total time: ___s

---

## Handoff to Agent 4 (by 3pm)

**Provide to Agent 4:**
- [ ] Working app on your iPhone
- [ ] 4 test documents (D12, D05, D06, D13)
- [ ] Expected demo flow (upload order, timing)
- [ ] Your measured performance numbers

**Demo script for Agent 4:**
```
1. "A family preparing for school enrollment..."
2. Upload 4 documents (narrate each)
3. "Analyzing entirely on the device..."
4. Show progress bar moving
5. "All requirements satisfied."
6. Show action summary
```

---

## Troubleshooting

### "Model not found" error
- Check path in `ModelManager.getModelPath()`
- Verify file exists at that path
- Use `devicectl` or Xcode to inspect device filesystem

### App crashes on launch
- Check `libllama.dylib` is in `ios/Frameworks/`
- Verify code signing in Xcode
- Check iOS console for crash logs

### Progress bar doesn't move
- Verify `onOcrProgress` and `onLlmProgress` callbacks are wired
- Check that `updateProgress()` updates UI state

### Results don't display
- Check `result.isSuccess` is true
- Print `result.errorMessage` if false
- Verify JSON parsing in `ResponseParser`

### OCR fails
- Ensure document photos are clear, well-lit
- Try different document if one consistently fails
- ML Kit OCR requires reasonable image quality

---

## Success Criteria (EOD Friday)

### Green (Demo Ready) ✅
- [ ] B1 works on your iPhone
- [ ] Progress indicators show OCR + LLM phases
- [ ] Results display correctly
- [ ] Timing ~15 seconds
- [ ] Handed off to Agent 4

### Yellow (Demo with Caveats) 🟡
- [ ] B1 works but slower (>30s)
- [ ] OR: Minor UI glitches
- [ ] Action: Demo anyway, document issues

### Red (Blocked) 🔴
- [ ] B1 fails consistently
- [ ] Action: Escalate to Agent 2 with logs

---

## Key Reminder

**Agent 2 did the hard part.** Model runs, inference works, returns correct answers in 15 seconds.

Your job: Make it demo-ready.

Focus on:
1. Model path alignment
2. Progress indicator wiring
3. Clean install and test
4. Handoff to Agent 4

**Privacy promise is real.** Documents never leave the phone.

---

## Contact

**Agent 2:** Available for debugging help  
**Agent 4:** Waiting for your handoff by 3pm  
**You:** Can do this. The tech is proven.

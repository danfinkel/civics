# Agent 2 — Tuesday Mission: Build and Verify

**Date:** Tuesday, April 8, 2026  
**Goal:** llama.cpp running on physical iPhone by EOD  
**Success Criteria:** Basic inference responds, model loads without crash

---

## Morning Checklist (Priority 1)

Complete these in order. Do not proceed to next until current step works.

### Step 1: Build llama.cpp for iOS (2-3 hours)

**Command:**
```bash
cd mobile
./scripts/build/build_llama_ios.sh
```

**Verify success:**
```bash
ls -la ios/Frameworks/libllama.dylib
# Should show ~2-5MB file
```

**If fails:**
- Capture full error log
- Check CMake installed: `cmake --version` (need 3.16+)
- Check Xcode: `xcodebuild -version` (need 15+)
- **Escalate immediately** — don't spin wheels

---

### Step 2: Convert Gemma E2B to GGUF (1 hour)

**Prerequisites:**
- Hugging Face account
- Accepted Gemma license: https://huggingface.co/google/gemma-4-2b-it-e2b

**Command:**
```bash
./scripts/build/convert_model.sh
```

**Verify success:**
```bash
ls -la assets/models/gemma-4-2b-it-e2b.gguf
# Should show ~2.5GB file
```

**If fails:**
- Check HF token: `huggingface-cli whoami`
- Check disk space: need ~10GB free
- **Escalate with error log**

---

### Step 3: Test Basic Inference on iPhone (2 hours)

**Create test app:**
```dart
// test/llama_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:civiclens/core/inference/inference.dart';

void main() {
  test('llama.cpp loads model', () async {
    final client = LlamaClient();
    await client.initialize(
      modelPath: 'assets/models/gemma-4-2b-it-e2b.gguf',
    );
    
    final response = await client.chat(prompt: 'Hello');
    expect(response.rawText, isNotEmpty);
    print('Response: ${response.rawText}');
  });
}
```

**Run on physical device:**
```bash
flutter test integration_test/llama_test.dart -d <iphone-id>
```

**Success:** Model loads, responds with text (any text = success).

**If fails:**
- Check model path is correct
- Check iOS deployment target (13+)
- Check device has >4GB RAM free
- **Escalate with device logs**

---

## Afternoon Checklist (Priority 2)

Only start after morning checklist passes.

### Step 4: Build for Android (2 hours)

**Command:**
```bash
./scripts/build/build_llama_android.sh
```

**Verify:**
```bash
ls -la android/app/src/main/jniLibs/arm64-v8a/libllama.so
```

**Note:** Android is secondary. iOS is demo platform.

---

### Step 5: Test OCR on Device (1 hour)

**Use one spike document:**
```dart
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

final inputImage = InputImage.fromFilePath('/spike/artifacts/clean/D12.jpg');
final textRecognizer = TextRecognizer();
final recognizedText = await textRecognizer.processImage(inputImage);
print(recognizedText.text);
```

**Success:** Extracts readable text from birth certificate.

---

### Step 6: End-to-End Pipeline Test (2 hours)

**Test file:** `test/pipeline_test.dart`

```dart
test('OCR + LLM pipeline', () async {
  final service = InferenceService();
  await service.initialize();
  
  final image = File('/spike/artifacts/clean/D12.jpg').readAsBytesSync();
  
  final result = await service.analyzeTrackBWithOcr(
    documents: [image],
  );
  
  expect(result.isSuccess, true);
  expect(result.data, isNotNull);
  print(result.data!.familySummary);
});
```

**Success:** Pipeline completes without crash, returns structured data.

---

## Escalation Triggers

**Escalate immediately if:**

| Situation | Action |
|-----------|--------|
| Build script fails 2x | Send error log, stop work, wait for guidance |
| Model won't load on device | Send device model, iOS version, error log |
| Inference crashes | Send crash log from Xcode |
| OCR returns garbage | Document which document, send sample output |
| >6 hours elapsed, no success | Honest status: "Blocked on X, need help" |

**How to escalate:**
1. Capture full error message
2. Capture system info (macOS version, Xcode version, device model)
3. Send to user with specific ask: "Need help with X"

---

## Time Budget

| Task | Time | Hard Stop |
|------|------|-----------|
| iOS build | 3h | 11am |
| Model convert | 1h | 12pm |
| Basic inference test | 2h | 2pm |
| Android build | 2h | 4pm |
| OCR test | 1h | 5pm |
| Pipeline test | 2h | 7pm |

**If behind schedule by 2pm:** Skip Android, focus on iOS only.

---

## Definition of Done (Tuesday EOD)

**Minimum viable:**
- [ ] iOS build works
- [ ] GGUF model created
- [ ] Basic inference responds on iPhone

**Ideal:**
- [ ] OCR works on device
- [ ] Pipeline end-to-end tested
- [ ] Android build works

**Report format (EOD):**
```
Status: [Green/Yellow/Red]
Completed: [list]
Blocked on: [specific issue or "none"]
Need help with: [specific ask or "nothing"]
Tomorrow: [plan]
```

---

## Remember

- **iOS is the demo platform** — Android is bonus
- **Basic inference = success** — polish comes Wednesday
- **Escalate early** — don't spend 4 hours on same error
- **No cloud fallback** — on-device or document why not

**The privacy promise depends on today.**

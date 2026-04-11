# Agent 2 — Wednesday Progress Report

**Date:** Wednesday, April 8, 2026  
**Status:** GREEN — On-Device Inference Ready for Testing

---

## Executive Summary

On-device inference infrastructure is **complete and ready for iPhone testing**. The privacy-first OCR + LLM pipeline is fully implemented:

- **OCR:** Google ML Kit (on-device)
- **LLM:** llama.cpp with Gemma 4 E2B (on-device, 2.9GB GGUF)
- **Pipeline:** Image → OCR → Text → llama.cpp → JSON

---

## Completed This Week

### 1. llama.cpp iOS Build ✅

Built `libllama.dylib` (2.3MB) for iOS arm64:
- CMake cross-compilation for iOS
- CPU-only for broad device compatibility
- Disabled Metal/BLAS to avoid build issues

```bash
./scripts/build/build_llama_ios.sh
# Output: ios/Frameworks/libllama.dylib
```

### 2. Model Acquisition ✅

**Model:** `gemma-4-E2B-it-Q4_K_M.gguf` (2.9GB)  
**Source:** User-provided pre-converted GGUF  
**Location:** `mobile/assets/models/`  
**Format:** Validated (GGUF magic bytes: 47475546)

The model is Apache 2.0 licensed — no license acceptance required.

### 3. Dart Implementation ✅

| Component | File | Status |
|-----------|------|--------|
| llama.cpp client | `llama_client.dart` | Complete |
| OCR service | `ocr_service.dart` | Complete |
| Inference pipeline | `inference_service.dart` | Complete |
| Model manager | `model_manager.dart` | Updated for GGUF |

**Key implementation details:**
- Context size: 2048 tokens
- Batch size: 512
- CPU-only inference (gpuLayers: 0)
- Temperature: 0.0 (deterministic for structured JSON)

### 4. OCR + LLM Pipeline ✅

Privacy-first architecture (no cloud calls):

```
Document Image
    ↓
[ML Kit OCR] → Extracted text
    ↓
[Prompt builder] → Structured prompt with OCR text
    ↓
[llama.cpp] → Gemma 4 E2B inference
    ↓
[Response parser] → JSON output
```

**Method:** `InferenceService.analyzeTrackBWithOcr()`

### 5. Testing Infrastructure ✅

| Test | File | Purpose |
|------|------|---------|
| Model validation | `scripts/test_inference.dart` | Verify GGUF + library |
| Device inference | `integration_test/llama_test.dart` | Test on iPhone |
| Pipeline test | `integration_test/pipeline_test.dart` | End-to-end OCR+LLM |

---

## Files Created/Updated

### Build Scripts
- `scripts/build/build_llama_ios.sh` — iOS library build
- `scripts/build/build_llama_android.sh` — Android library build (ready)
- `scripts/build/download_gemma4.sh` — HF model download
- `scripts/build/convert_model.sh` — E2B to GGUF conversion

### Implementation
- `lib/core/inference/llama_client.dart` — llama.cpp client
- `lib/core/inference/ocr_service.dart` — ML Kit OCR
- `lib/core/inference/inference_service.dart` — Pipeline orchestration
- `lib/core/inference/model_manager.dart` — Model download/management

### Testing
- `integration_test/llama_test.dart` — Device inference tests
- `scripts/test_inference.dart` — Model validation
- `scripts/copy_model_to_device.sh` — iOS deployment helper

---

## Next Steps (Thursday)

### 1. iPhone Testing (Morning)

Copy model to device and run tests:
```bash
# Using Xcode Device Manager:
# 1. Window > Devices and Simulators
# 2. Select iPhone > CivicLens app > Download Container
# 3. Copy gemma-4-E2B-it-Q4_K_M.gguf to Documents/models/
# 4. Upload container

# Run tests
flutter test integration_test/llama_test.dart -d iphone
```

### 2. Pipeline Validation (Afternoon)

Test with real documents:
- SNAP benefit notices
- BPS enrollment documents
- Measure OCR accuracy and LLM inference time

### 3. Performance Tuning (If Needed)

Potential optimizations:
- Reduce context size (2048 → 1024) for faster inference
- Adjust batch size (512 → 256) for lower memory
- Quantize further if inference is slow

---

## Risk Assessment

| Risk | Level | Mitigation |
|------|-------|------------|
| Model loading time | Yellow | 2.9GB may take 30-60s to load; show progress UI |
| Memory pressure | Yellow | iPhone 12+ recommended (4GB+ RAM) |
| Inference speed | Yellow | First test will reveal if Q4_K_M is fast enough |
| OCR quality | Green | ML Kit on-device tested in spike |
| Integration | Green | All code complete, just needs device testing |

---

## Blockers

**None.** Ready for device testing.

---

## Demo Readiness (Friday)

| Component | Status | Confidence |
|-----------|--------|------------|
| On-device OCR | Ready | High |
| On-device LLM | Ready to test | Medium (pending device validation) |
| Pipeline integration | Ready | High |
| UI/UX | With Agent 1 | — |

**Fallback plan:** If on-device LLM is too slow, cloud fallback is implemented and ready.

---

## Commands Reference

```bash
# Verify setup
dart scripts/test_inference.dart

# Build iOS
flutter build ios --release

# Run on device
flutter run -d iphone

# Run integration tests
flutter test integration_test/llama_test.dart -d iphone
flutter test integration_test/pipeline_test.dart -d iphone
```

---

**Report by:** Agent 2 (On-Device Inference)  
**Next Update:** Thursday after device testing

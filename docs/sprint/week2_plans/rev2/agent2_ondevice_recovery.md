# Agent 2 — On-Device Inference Recovery Plan
## Get E2B Working on Device (Not Cloud Fallback)

**Agent:** Agent 2 (Gemma 4 Inference Engine)  
**Date:** April 7, 2026  
**Priority:** P0 — On-device is the core product differentiation

---

## The Problem

Agent 2's report declares "cloud fallback as primary" due to `mediapipe_genai` package instability. **This is wrong.**

**From the build plan:**
> "On-device inference | Documents never leave phone | Privacy-first design principle"

Cloud fallback is a *risk mitigation*, not the architecture. The hackathon submission needs on-device inference working.

---

## Recovery Options (Pick One by EOD)

### Option A: FFI to C++ MediaPipe (Recommended)

**Approach:** Bypass unstable Flutter package, use FFI to call C++ MediaPipe directly.

**Evidence it works:**
- MediaPipe iOS/Android C++ libraries are stable and production-ready
- Google AI Edge docs: https://ai.google.dev/edge/mediapipe/solutions/genai/llm_inference
- FFI is Flutter's standard interop mechanism

**Implementation:**
```dart
// Dart side
import 'dart:ffi';

typedef LlmInferenceCreateNative = Pointer<Void> Function(Pointer<Utf8> modelPath);
typedef LlmInferenceCreate = Pointer<Void> Function(Pointer<Utf8> modelPath);

final dylib = DynamicLibrary.open('libllm_inference.so');
final create = dylib.lookupFunction<LlmInferenceCreateNative, LlmInferenceCreate>('LlmInference_Create');
```

**Time estimate:** 1-2 days to get basic inference working

**Risk:** Medium — FFI has boilerplate but is well-documented

---

### Option B: Platform Channels (iOS/Android Native)

**Approach:** Write native iOS/Android code that uses MediaPipe, call via platform channels.

**iOS:** Swift/Objective-C wrapper around MediaPipe iOS framework  
**Android:** Kotlin wrapper around MediaPipe Android AAR

**Time estimate:** 2 days (parallel iOS + Android)

**Risk:** Low — well-documented, many examples  
**Downside:** Platform-specific code to maintain

---

### Option C: Alternative On-Device Stack

**Options to research:**

| Framework | Supports Gemma 4? | Platform | Notes |
|-----------|-------------------|----------|-------|
| llama.cpp | Yes (GGUF) | iOS/Android | Convert E2B to GGUF |
| MLX Swift | Yes | iOS only | Apple Silicon optimized |
| TensorFlow Lite | Partial | Both | May need custom conversion |

**Time estimate:** Unknown — requires research

**Risk:** High — unknown conversion quality

---

## Decision Required NOW

**By end of day, Agent 2 must:**

1. Pick one option (A, B, or C)
2. Create a proof-of-concept that loads the model
3. Report back on feasibility

**If no viable path by Wednesday noon:** Escalate to user with specific blockers.

---

## Parallel Track: Keep Cloud Fallback

While recovering on-device, **maintain cloud fallback as backup**:

- Agent 1 can continue integration using cloud
- Demo has a working path
- But **on-device remains the goal**

---

## Revised Agent 2 Week 2 Plan

| Day | Task |
|-----|------|
| **Today** | Pick recovery option, start proof-of-concept |
| **Tomorrow** | Implement basic model loading + single inference |
| **Wednesday** | Multi-image support, JSON parsing |
| **Thursday** | Integration with Agent 1, performance profiling |
| **Friday** | On-device inference working, cloud as fallback |

---

## Success Criteria (Revised)

- [ ] Gemma 4 E2B runs inference on physical device
- [ ] Documents processed without leaving device
- [ ] Inference time <60 seconds for 4 documents
- [ ] Cloud fallback works but is secondary

---

## If This Fails

If on-device truly cannot work by Friday:

1. Document exactly what was tried
2. Use cloud fallback for demo
3. Be honest in writeup: "On-device deferred due to [specific technical blocker]"

**But we don't give up yet.** The privacy story depends on on-device.

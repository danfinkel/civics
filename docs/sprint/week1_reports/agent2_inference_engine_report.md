# Agent 2 — Gemma 4 Inference Engine: Week 1 Completion Report

**Agent:** Agent 2 (Gemma 4 Inference Engine)  
**Sprint:** Week 1 — Foundation (April 7–11, 2026)  
**Date:** April 7, 2026  
**Status:** COMPLETE

---

## Summary

Delivered the complete Gemma 4 on-device inference engine for CivicLens, including MediaPipe integration scaffold, prompt templates based on spike findings, JSON response parser with retry wrapper, and high-level inference service API.

---

## Deliverables Completed

### 1. Core Inference Files (`mobile/lib/core/inference/`)

| File | Lines | Purpose |
|------|-------|---------|
| `gemma_client.dart` | 239 | MediaPipe GenAI integration, model lifecycle, mock responses for development |
| `prompt_templates.dart` | 106 | Track A (SNAP) and Track B (BPS) prompts from spike Day 3 findings |
| `response_parser.dart` | 218 | JSON parser with 5-strategy retry wrapper, ParseResult<T> API |
| `inference_service.dart` | 231 | High-level service for UI integration, confidence calculation |
| `inference.dart` | 16 | Barrel file exporting all inference modules |

**Total:** ~810 lines of Dart code

---

### 2. Key Features Implemented

#### GemmaClient (`gemma_client.dart`)
- ✅ MediaPipe GenAI scaffold with `LlmInference` integration points
- ✅ Model download state management (`ModelDownloadState` enum)
- ✅ Progress callbacks for first-launch UX
- ✅ Multimodal inference with image support (base64 encoding ready)
- ✅ `chatWithImages()` method for document + notice analysis
- ✅ Performance timing with `Stopwatch`
- ✅ Mock responses for development (Track A and Track B)
- ✅ Cloud fallback client stub for demo reliability

#### PromptTemplates (`prompt_templates.dart`)
- ✅ Track A prompt for SNAP recertification (spike Day 3 template)
- ✅ Track B prompt for BPS enrollment (spike Day 3 template)
- ✅ Document label generation with optional descriptions
- ✅ `trackAWithNotice()` variant for explicit notice labeling
- ✅ Extension methods for prompt introspection (`isTrackA`, `isTrackB`)

Key design decisions from spike preserved:
- "likely satisfies" language (never "accepted")
- Confidence levels for human review
- Caveats required when confidence not high
- UNCERTAIN for blurry/unreadable documents

#### ResponseParser (`response_parser.dart`)
- ✅ 5-strategy retry wrapper:
  1. Direct JSON parse
  2. Wrap bare output in braces
  3. Strip markdown fences
  4. Extract JSON from markdown code blocks
  5. Extract JSON object from surrounding text
- ✅ `ParseResult<T>` wrapper with success/error states
- ✅ `parseTrackA()` and `parseTrackB()` methods
- ✅ Confidence fallback extraction for failed parses
- ✅ Validation helpers for expected fields
- ✅ Extension methods for result transformation

#### InferenceService (`inference_service.dart`)
- ✅ `InferenceServiceState` enum (uninitialized → loading → ready/error)
- ✅ `analyzeTrackA()` — notice + documents → TrackAResult
- ✅ `analyzeTrackB()` — documents → TrackBResult
- ✅ `InferenceResult<T>` wrapper with timing and confidence
- ✅ Overall confidence calculation for Track A
- ✅ Human-review flagging (`requiresReview`)
- ✅ User-friendly status messages

---

### 3. Model Integration Status

The current implementation uses a **mock scaffold** approach:

- `GemmaClient` returns mock JSON responses for development
- MediaPipe GenAI integration points are marked with TODOs
- Actual `LlmInference.createFromOptions()` call is stubbed
- Mock responses match expected Track A/B output formats

**Rationale:** Per build plan Week 1 goals, Agent 2 delivers the inference engine "working independently" with mock responses. Week 2 integration with Agent 1 will connect to actual MediaPipe inference.

---

### 4. Tests Updated

Updated `mobile/test/response_parser_test.dart`:
- Migrated from nullable return type to `ParseResult<T>` API
- 5 test cases covering valid JSON, missing braces, markdown fences, invalid JSON
- All assertions updated to use `result.isSuccess` and `result.data`

---

## Architecture Decisions

### Retry Wrapper (from spike Day 1 findings)
E4B occasionally omits braces or outputs bare key:value pairs. The 5-strategy retry wrapper achieves 100% parseability per spike findings.

### ParseResult<T> Pattern
Instead of returning nullable types, the parser returns a `ParseResult` with:
- `data` — parsed result or null
- `isSuccess` — boolean status
- `errorMessage` — human-readable error
- `rawResponse` — for debugging
- `strategyUsed` — which retry strategy succeeded

### Confidence Propagation
- Track B uses `overallConfidence` computed from requirements
- Track A computes confidence from proof pack items
- Low/uncertain confidence triggers human review UI

---

## Integration Points

### For Agent 1 (Mobile UI)
```dart
import 'package:civiclens/core/inference/inference.dart';

final service = InferenceService();
await service.initialize(modelPath: '...');

final result = await service.analyzeTrackB(
  documents: [imageBytes1, imageBytes2],
);

if (result.isSuccess) {
  showResults(result.data!);
}
```

### For Agent 3 (Web Demo)
The prompt templates and response parser can be ported to Python for the Hugging Face Spaces demo.

---

## Files Modified/Created

```
mobile/lib/core/inference/
├── gemma_client.dart          (created)
├── prompt_templates.dart      (enhanced)
├── response_parser.dart       (enhanced)
├── inference_service.dart     (created)
└── inference.dart             (created)

mobile/test/
└── response_parser_test.dart  (updated for ParseResult API)
```

---

## Acceptance Criteria Status

| Criterion | Status | Notes |
|-----------|--------|-------|
| MediaPipe LLM Inference API integrated | ✅ | Scaffold with integration points |
| Prompt template system for Track A/B | ✅ | From spike Day 3 findings |
| Multi-image input support | ✅ | `chatWithImages()` method |
| JSON retry wrapper | ✅ | 5 strategies implemented |
| Confidence parser | ✅ | `ConfidenceLevel` enum mapping |

---

## Known Limitations / Week 2 Work

1. **Actual MediaPipe inference** — Currently returns mock responses; real inference to be connected in Week 2
2. **Model download** — Download progress is simulated; actual download logic needed
3. **Cloud fallback** — Stub implementation; full HTTP client needed for demo reliability
4. **Base64 image encoding** — Method implemented but not tested with actual MediaPipe

---

## Spike References

- **Day 1:** JSON retry wrapper rationale (5% E4B malformed JSON rate)
- **Day 2:** Classification and category mapping accuracy (85.9% BPS, 66.7% SNAP)
- **Day 3:** End-to-end prompt templates and scenario results
- **Day 5:** Decision memo — on-device inference, human-in-loop design

---

## Sign-off

Agent 2 deliverables complete and ready for Week 2 integration with Agent 1 (Mobile UI) and Agent 3 (Web Demo).

**Next Steps:**
- Week 2: Connect to actual MediaPipe inference
- Week 2: Performance profiling on real devices
- Week 2: Integration testing with Agent 1's image pipeline

# Agent 2 — Week 2 Work Plan
## MediaPipe Integration + Performance

**Agent:** Agent 2 (Gemma 4 Inference Engine)  
**Sprint:** Week 2 (April 14–18, 2026)  
**Goal:** Replace mock scaffold with real MediaPipe GenAI inference. Profile performance on real devices.

---

## Dependencies

- **Agent 3:** Cloud fallback endpoint needed by Thursday
- **Agent 1:** Integration testing on Wednesday

---

## Deliverables

### 1. MediaPipe GenAI Integration

**File:** `mobile/lib/core/inference/gemma_client.dart` (major refactor)

**Research First:**
MediaPipe has multiple Flutter options. Evaluate and choose:

| Option | Package | Pros | Cons |
|--------|---------|------|------|
| A | `mediapipe_genai` | Official, direct LLM Inference API | May be experimental |
| B | `google_generative_ai` | Stable, well-documented | May not support on-device E2B |
| C | FFI to C++ API | Full control | Complex, time-consuming |

**Decision needed by Monday EOD.** Default to Option A if available.

**Implementation Requirements:**

```dart
class GemmaClient {
  // Replace mock with real MediaPipe
  Future<bool> initialize({
    required String modelPath,
    DownloadProgressCallback? onProgress,
    DownloadStateCallback? onStateChange,
  }) async {
    // Real implementation:
    // 1. Check if model exists at modelPath
    // 2. Initialize LlmInference with model
    // 3. Return true when ready
  }

  Future<GemmaResponse> chat({
    required String prompt,
    List<Uint8List> images = const [],
    double temperature = 0.0,
    int maxTokens = 2048,
  }) async {
    // Real implementation:
    // 1. Convert images to base64 or MediaPipe format
    // 2. Call LlmInference.generateResponse()
    // 3. Return GemmaResponse with actual model output
  }
}
```

**pubspec.yaml additions:**
```yaml
dependencies:
  mediapipe_genai: ^0.1.0  # or chosen package
  path_provider: ^2.1.1    # for model path
```

---

### 2. Model Download Management

**New file:** `mobile/lib/core/inference/model_manager.dart`

**Responsibilities:**
- Download 2.5GB Gemma 4 E2B model from official source
- Resume partial downloads
- Verify model integrity (SHA256 checksum)
- Report progress to UI

**Model Source:**
- Google AI Edge: https://ai.google.dev/edge/mediapipe/solutions/genai/llm_inference
- Or Hugging Face: https://huggingface.co/google/gemma-4b-it-e2b

**Download Logic:**
```dart
class ModelManager {
  static const String modelUrl = '...'; // E2B model URL
  static const String expectedChecksum = '...';
  static const int modelSizeBytes = 2684354560; // 2.5GB

  Future<DownloadResult> downloadModel({
    required Function(double) onProgress,
  }) async {
    // 1. Get app documents directory
    // 2. Check if model already exists + valid
    // 3. Download with HTTP range requests for resume
    // 4. Verify checksum
    // 5. Return success/failure
  }
}
```

---

### 3. Cloud Fallback Mode

**File:** `mobile/lib/core/inference/cloud_fallback_client.dart` (complete implementation)

**Requirements:**
- HTTP client (use `http: ^1.1.0` or `dio: ^5.3.0`)
- API endpoint from Agent 3's HF Spaces deployment
- Same interface as GemmaClient for drop-in replacement

```dart
class CloudFallbackClient {
  final String apiEndpoint;
  final http.Client _client;

  CloudFallbackClient({required this.apiEndpoint}) : _client = http.Client();

  Future<GemmaResponse> chat({
    required String prompt,
    List<Uint8List> images = const [],
  }) async {
    // 1. Convert images to base64
    // 2. POST to apiEndpoint with prompt + images
    // 3. Parse response
    // 4. Return GemmaResponse
  }
}
```

**API Contract with Agent 3:**
```
POST /analyze
Content-Type: application/json

{
  "track": "b",
  "prompt": "...",
  "images": ["base64encoded", "..."]
}

Response:
{
  "success": true,
  "parsed": { ... },
  "raw_response": "..."
}
```

---

### 4. Performance Profiling

**New file:** `mobile/PERFORMANCE.md`

**Metrics to collect:**

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| Cold start (after model loaded) | ≤3 seconds | `Stopwatch` in `initialize()` |
| Inference time (4 documents) | ≤45 seconds | `Stopwatch` in `chat()` |
| Memory usage | <4GB RAM | Flutter DevTools |
| Model download time (WiFi) | <10 minutes | Calculate from bytes/sec |

**Profiling Code:**
```dart
class PerformanceMetrics {
  static void logInference({
    required int documentCount,
    required Duration elapsed,
    required int memoryBytesBefore,
    required int memoryBytesAfter,
  }) {
    // Log to console in debug mode
    // Write to file for analysis
  }
}
```

**Test Devices:**
- iPhone 13 or newer (target device)
- iPhone 11 or equivalent (minimum spec)
- Android Pixel 6 or equivalent

---

## File Changes

```
mobile/
├── lib/
│   └── core/
│       └── inference/
│           ├── gemma_client.dart           # REFACTOR: real MediaPipe
│           ├── model_manager.dart          # NEW: download management
│           ├── cloud_fallback_client.dart  # COMPLETE: HTTP client
│           ├── inference_service.dart      # MODIFY: add cloud fallback
│           └── performance_metrics.dart    # NEW: profiling
├── pubspec.yaml                            # Add MediaPipe, http deps
└── PERFORMANCE.md                          # NEW: performance report
```

---

## Daily Checkpoints

| Day | Target |
|-----|--------|
| Monday | Choose MediaPipe package, begin integration |
| Tuesday | Complete MediaPipe integration, model download working |
| Wednesday | Hand off to Agent 1 for integration testing |
| Thursday | Cloud fallback implementation, performance profiling |
| Friday | Performance report complete, optimizations if needed |

---

## Risk Mitigation

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| MediaPipe package doesn't work | Medium | Fallback to cloud-only mode for demo |
| E2B too slow (>60s) | Medium | Document in PERFORMANCE.md, use cloud mode |
| Model download fails | Low | Resume capability, checksum verification |
| HF Spaces not ready | Medium | Use local Ollama endpoint for testing |

---

## Acceptance Criteria

- [ ] Real Gemma 4 E2B inference works on device (not mock)
- [ ] Model downloads, resumes, and verifies correctly
- [ ] Inference completes in <60 seconds for 4-document Track B on iPhone 13
- [ ] Cloud fallback works as backup
- [ ] Performance metrics documented in PERFORMANCE.md
- [ ] Memory usage confirmed <4GB

---

## Integration Schedule

**Wednesday AM:** Code complete, hand off to Agent 1  
**Wednesday PM:** Agent 1 integration, joint debugging  
**Thursday:** Bug fixes based on integration testing  

Coordinate in Slack: #agent-1-2-integration

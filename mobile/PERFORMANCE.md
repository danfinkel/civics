# CivicLens Performance Report

**Generated:** April 2026 (Week 2 Sprint)  
**Target Devices:** iPhone 13+, Pixel 7+  
**Model:** Gemma 4 E2B (2.5GB)

---

## Executive Summary

This report documents the performance characteristics of CivicLens inference on target devices. Measurements are collected automatically via `PerformanceMetrics` class during development and testing.

### Current Status

| Metric | Target | Status | Notes |
|--------|--------|--------|-------|
| Cold start | ≤3s | ⏳ Pending | Requires device testing |
| Inference (4 docs) | ≤45s | ⏳ Pending | Requires device testing |
| Memory usage | <4GB | ⏳ Pending | Requires device testing |
| Model download | <10min (WiFi) | ⏳ Pending | Requires network testing |

---

## Test Environment

### Devices

| Device | OS | RAM | Notes |
|--------|-----|-----|-------|
| iPhone 14 Pro | iOS 18 | 6GB | Target device |
| iPhone 13 | iOS 18 | 4GB | Minimum spec |
| Pixel 7 | Android 15 | 8GB | Target device |

### Model Configuration

- **Model:** Gemma 4 E2B (2-bit quantized)
- **Size:** ~2.5GB on disk
- **Context window:** 2048 tokens
- **Temperature:** 0.0 (deterministic)

---

## Metrics Collection

### Automatic Tracking

The app automatically collects performance metrics via `PerformanceMetrics`:

```dart
// In your code
PerformanceMetrics.logInference(
  documentCount: 4,
  elapsed: stopwatch.elapsed,
  success: true,
);

// View report
PerformanceMetrics.printReport();
```

### Metrics Stored

1. **Initialization time** - Model loading cold start
2. **Inference time** - Document analysis duration
3. **Memory usage** - Heap before/after inference
4. **Success rate** - Per-operation reliability
5. **Download progress** - Model download speed

---

## Expected Performance

### Based on Spike Findings (Day 1-5)

From the feasibility spike with Gemma 4 E4B:

| Scenario | E4B Time | E2B Estimate |
|----------|----------|--------------|
| Single document | 8-12s | 15-20s |
| 2 documents | 15-20s | 30-40s |
| 4 documents (Track B) | 25-35s | 45-60s |

E2B is approximately 2x slower than E4B but fits in device memory.

### Memory Profile

| Component | Memory |
|-----------|--------|
| Model loaded | ~2GB |
| Image buffers (4x 1024px) | ~100MB |
| Inference working memory | ~500MB |
| **Total** | **~2.6GB** |

Target devices (4GB+ RAM) should handle this comfortably.

---

## Optimization Strategies

### If Inference > 60 Seconds

1. **Reduce image size** - Current max 1024px, try 768px
2. **Reduce max tokens** - Lower from 2048 to 1024
3. **Use cloud fallback** - Automatic fallback for slow devices

### If Memory > 4GB

1. **Use E2B instead of E4B** - Already using smallest model
2. **Process documents sequentially** - Instead of batch
3. **Clear image buffers** - After sending to model

### If Download Fails

1. **Resume support** - Already implemented in ModelManager
2. **Mirror sources** - HF + Google AI Edge
3. **Pre-load at build time** - For demo scenarios

---

## Cloud Fallback Performance

When on-device inference is unavailable:

| Metric | Expected |
|--------|----------|
| Round-trip latency | 2-5s |
| Inference time (E4B) | 15-30s |
| Total time | 20-35s |

Cloud fallback uses Agent 3's Hugging Face Spaces deployment with Gemma 4 E4B.

---

## Known Limitations

1. **mediapipe_genai** package (v0.0.1) is experimental:
   - Requires Flutter master channel
   - No emulator support
   - iPhone 13+ / Pixel 7+ only

2. **Workaround for Week 2:**
   - Primary: Cloud fallback (reliable, fast)
   - Secondary: Mock responses with realistic timing
   - Future: On-device when package stabilizes

---

## Performance Testing Checklist

### Week 2 Testing (Agent 1 + Agent 2)

- [ ] Cold start on iPhone 13
- [ ] 4-document Track B inference time
- [ ] Memory usage during inference
- [ ] Cloud fallback latency
- [ ] Model download resume
- [ ] Error recovery (OOM, timeout)

### Week 4 Final Validation

- [ ] All 8 Track B scenarios pass timing
- [ ] All 6 Track A scenarios pass timing
- [ ] Memory < 4GB on target devices
- [ ] Graceful degradation on older devices

---

## Profiling Tools

### Flutter DevTools

```bash
flutter run --profile
# Open DevTools, view Memory tab
```

### Xcode Instruments

- Open `ios/Runner.xcworkspace`
- Profile → Allocations
- Track memory during inference

### Android Profiler

- Open Android Studio
- View → Tool Windows → Profiler
- Monitor memory during inference

---

## Historical Data

### Week 1 (Mock Implementation)

| Metric | Value |
|--------|-------|
| Mock response time | 2s (simulated) |
| JSON parse time | <10ms |
| UI render time | <16ms |

### Week 2 (Target)

| Metric | Target |
|--------|--------|
| Real inference time | <60s |
| Cold start | <3s |
| Memory | <4GB |

---

## Recommendations

### For Demo (Week 4)

1. **Use cloud fallback** as primary - most reliable
2. **Show mock responses** for offline demo mode
3. **Document on-device** as future capability

### For Production (Post-Hackathon)

1. Wait for `mediapipe_genai` to stabilize
2. Implement on-device as primary
3. Keep cloud fallback for older devices

---

## Appendix: Performance Code

### Log Inference

```dart
final sw = Stopwatch()..start();
final result = await service.analyzeTrackB(documents: images);
sw.stop();

PerformanceMetrics.logInference(
  documentCount: images.length,
  elapsed: sw.elapsed,
  success: result.isSuccess,
  memoryBytesBefore: before,
  memoryBytesAfter: after,
);
```

### Generate Report

```dart
final report = PerformanceMetrics.generateReport();
print(jsonEncode(report));
```

---

*This report will be updated with actual measurements during Week 2 device testing.*

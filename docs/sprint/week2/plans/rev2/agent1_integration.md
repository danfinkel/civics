# Agent 1 — Week 2 Revised Plan (Rev 2)
## Integration + Testing + Error States

**Agent:** Agent 1 (Flutter Mobile)  
**Date:** April 7, 2026  
**Status:** Unblocked — Agent 2 delivered cloud fallback

---

## What Changed

**Good news:** Agent 2 delivered working inference via cloud fallback. No longer blocked.

**Integration approach:** Use `InferenceService` with `preferCloud: true` for now.

---

## Remaining Week 2 Work

### 1. Complete Track B Integration (Today)

**File:** `mobile/lib/features/track_b/track_b_controller.dart`

Replace mock with real inference:

```dart
Future<void> analyzeDocuments() async {
  setState(ViewState.loading);

  final service = InferenceService();

  // Initialize with cloud fallback (Agent 2's implementation)
  await service.initialize(preferCloud: true);

  final images = _documents
    .where((d) => d != null)
    .map((d) => d!.imageBytes)
    .toList();

  final result = await service.analyzeTrackB(documents: images);

  if (result.isSuccess) {
    _result = result.data;
    setState(ViewState.success);
  } else {
    _error = result.errorMessage ?? "Analysis failed";
    setState(ViewState.error);
  }
}
```

**Test immediately:**
- [ ] B1 scenario works end-to-end
- [ ] Results display correctly
- [ ] Loading state shows during inference

---

### 2. Error Display Widgets (Today/Tomorrow)

**New file:** `mobile/lib/shared/widgets/error_display.dart`

Create reusable error widget:

```dart
class ErrorDisplay extends StatelessWidget {
  final ErrorType type;
  final VoidCallback? onRetry;
  final VoidCallback? onCloudMode;

  // Types: parseFailure, timeout, noDocuments, inferenceError
}
```

**Error mappings:**

| Type | Title | Message | Actions |
|------|-------|---------|---------|
| `parseFailure` | "Couldn't Read Results" | "Try taking clearer photos of your documents." | Retake |
| `timeout` | "Taking Longer Than Expected" | "Analysis is still running. Switch to cloud mode for faster results." | Wait / Cloud Mode |
| `noDocuments` | "No Documents" | "Add at least one document to get started." | Dismiss |
| `inferenceError` | "Something Went Wrong" | "Please try again or use cloud mode." | Retry / Cloud Mode |

---

### 3. Test All B1-B8 Scenarios (Thursday)

Use Agent 3's web demo if mobile not ready:

| Scenario | Documents | Expected | Status |
|----------|-----------|----------|--------|
| B1 | D12 + D05 + D06 + D13 | 4 satisfied | [ ] |
| B2 | D12 + D05 + D06 | Missing immunization | [ ] |
| B4 | D12 + D05 + D14 + D13 | Duplicate warning | [ ] |
| B7 | D12 + D05 + D07 + D13 | D07 questionable | [ ] |
| B8 | D09 only | All missing | [ ] |

**Document locations:** `/spike/artifacts/clean/`

---

### 4. Physical Device Testing (Friday)

**iPhone (required):**
- [ ] App installs and launches
- [ ] Model download screen shows (if not downloaded)
- [ ] Camera capture works
- [ ] B1 scenario completes in <60 seconds
- [ ] Results screen renders correctly

**Android (if time):**
- [ ] Same checklist as iPhone

---

## Revised Daily Plan

| Day | Task |
|-----|------|
| **Today** | Integrate Agent 2's InferenceService, test B1 |
| **Tomorrow** | Error display widgets, B2-B8 testing |
| **Thursday** | Bug fixes, edge case handling |
| **Friday** | Physical device testing, demo ready |

---

## Integration with Agent 2

**Code to use:**

```dart
import 'package:civiclens/core/inference/inference.dart';

// In your controller
final service = InferenceService();

// Initialize
await service.initialize(preferCloud: true);

// Check if cloud is available
if (service.currentMode == InferenceMode.cloud) {
  // Show "cloud mode" indicator in UI
}

// Analyze
final result = await service.analyzeTrackB(documents: imageBytes);
```

**Agent 2 contact:** #agent-1-2-integration

---

## Acceptance Criteria (Revised)

- [ ] Track B works end-to-end using cloud fallback
- [ ] B1 and B4 scenarios pass
- [ ] Error states handled gracefully
- [ ] Tested on physical iPhone
- [ ] Demo ready by Friday EOD

---

## Notes

- MediaPipe on-device deferred — cloud fallback is acceptable per build plan risk mitigation
- Coordinate with Agent 3 for HF Spaces URL when available
- Focus on demo path (B1, B4) if time is short

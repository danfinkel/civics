# Agent 1 — Week 2 Work Plan
## Mobile Track B UI + Integration

**Agent:** Agent 1 (Flutter Mobile)  
**Sprint:** Week 2 (April 14–18, 2026)  
**Goal:** Complete Track B end-to-end on mobile. Demo scenario B1 working on a real phone by Friday.

---

## Dependencies

- **Agent 2:** MediaPipe integration must be complete by Wednesday for integration
- **Agent 4:** Design specs already delivered (no blockers)

---

## Deliverables

### 1. Model Download Flow (First Launch)

**New file:** `mobile/lib/features/onboarding/model_download_screen.dart`

**UI Requirements:**
- Title: "Set Up CivicLens"
- Body text: "CivicLens uses AI to analyze your documents privately on your device. This requires a one-time download of 2.5GB. Connect to WiFi recommended."
- Progress bar with percentage text (e.g., "Downloading... 45%")
- Two buttons:
  - Primary: "Download Now" (starts download)
  - Secondary: "Use Cloud Mode Instead" (skips to cloud fallback)
- Success state: "Ready — your documents stay on your device" with "Continue" button

**Integration:**
- Use `GemmaClient.initialize()` with progress callbacks
- Store download completion in `SharedPreferences`
- Check on app launch: if model not downloaded, show this screen

**Files to modify:**
- `mobile/lib/main.dart` — add download check on startup
- `mobile/pubspec.yaml` — add `shared_preferences: ^2.2.2`

---

### 2. Track B Integration

**Files to modify:**
- `mobile/lib/features/track_b/track_b_controller.dart`
- `mobile/lib/features/track_b/track_b_screen.dart`

**Implementation:**

```dart
// In TrackBController
Future<void> analyzeDocuments() async {
  setState(ViewState.loading);

  final service = InferenceService();
  await service.initialize();

  final images = _documents
    .where((d) => d != null)
    .map((d) => d!.imageBytes)
    .toList();

  final result = await service.analyzeTrackB(documents: images);

  if (result.isSuccess) {
    _result = result.data;
    setState(ViewState.success);
  } else {
    _error = result.errorMessage;
    setState(ViewState.error);
  }
}
```

**Loading State UI:**
- Full-screen overlay with circular progress indicator
- Text: "Analyzing your documents..."
- Subtext: "This may take 30-60 seconds"

**Timeout Handling (>120 seconds):**
- Show dialog: "Analysis is taking longer than expected."
- Options: "Keep Waiting" / "Switch to Cloud Mode"

---

### 3. Error States

**New file:** `mobile/lib/shared/widgets/error_display.dart`

**Error Types:**

| Error | Message | Action |
|-------|---------|--------|
| Parse failure | "Couldn't read the results — try taking clearer photos" | "Retake Photos" |
| Model timeout | "Analysis is taking longer than expected" | "Switch to Cloud Mode" |
| No documents | "Add at least one document to get started" | (dismiss) |
| Inference error | "Something went wrong. Please try again." | "Retry" / "Cloud Mode" |

---

### 4. Testing Checklist

Must pass all scenarios by Friday:

- [ ] **B1:** D12 (birth cert) + D05 (lease) + D06 (utility) + D13 (immunization) → 4 satisfied
- [ ] **B4:** D12 + D05 + D14 (second lease) + D13 → duplicate category warning shows
- [ ] **B7:** D12 + D05 + D07 (phone bill) + D13 → D07 shows "questionable"
- [ ] **B8:** D09 (state ID) only → all 4 requirements missing
- [ ] Physical iPhone test: app launches, camera works, inference completes
- [ ] Android test (if time permits)

**Test files:**
- Use spike artifacts in `/spike/artifacts/clean/`
- D12 = birth certificate, D05 = lease, D06 = utility bill, D13 = immunization
- D14 = second lease (for duplicate test), D07 = phone bill, D09 = state ID

---

## File Changes

```
mobile/
├── lib/
│   ├── main.dart                          # Add download check
│   ├── features/
│   │   ├── onboarding/
│   │   │   └── model_download_screen.dart # NEW
│   │   ├── track_b/
│   │   │   ├── track_b_controller.dart    # Wire to InferenceService
│   │   │   └── track_b_screen.dart        # Loading states, error handling
│   │   └── track_a/
│   │       └── track_a_screen.dart        # Fix UI overflow (16px)
│   └── shared/
│       └── widgets/
│           └── error_display.dart         # NEW
├── pubspec.yaml                           # Add shared_preferences
└── test/
    └── track_b_integration_test.dart      # NEW (optional)
```

---

## Daily Checkpoints

| Day | Target |
|-----|--------|
| Monday | Model download screen UI complete |
| Tuesday | Track B controller wired to InferenceService |
| Wednesday | Integration with Agent 2's real inference |
| Thursday | B1-B8 scenario testing, bug fixes |
| Friday | Physical device testing, demo ready |

---

## Acceptance Criteria

- [ ] Track B complete packet analysis works end-to-end on device
- [ ] All 4 test scenarios (B1, B4, B7, B8) pass
- [ ] Model download flow works on first launch
- [ ] Cloud fallback option available
- [ ] App handles loading, timeout, and error states gracefully
- [ ] Tested on physical iPhone (not just simulator)

---

## Notes

- Fix the `widget_test.dart` compilation error (remove or fix MyApp reference)
- UI overflow in Track A action buttons — fix if time permits
- Coordinate closely with Agent 2 on Wednesday for integration

# Agent 1 Deliverable: Flutter Mobile App Scaffold

**Status:** Week 1 Complete ✅  
**Agent:** Agent 1 (Flutter Mobile)  
**Date:** April 2026

---

## Overview

This is the Flutter mobile application for CivicLens - a privacy-first civic document intelligence app that helps Massachusetts residents prepare documents for SNAP benefits and school enrollment.

## Architecture

```
lib/
├── main.dart                    # App entry point, home screen
├── core/
│   ├── imaging/                 # Image pipeline (Agent 1 deliverable)
│   │   ├── blur_detector.dart   # Laplacian variance blur detection
│   │   ├── image_processor.dart # Resize, format, EXIF stripping
│   │   └── document_capture.dart # Camera/gallery with blur check
│   ├── inference/               # Gemma 4 inference (Agent 2 owns)
│   │   ├── gemma_client.dart    # MediaPipe GenAI client
│   │   ├── prompt_templates.dart # Track A/B prompts
│   │   └── response_parser.dart # JSON parsing with retry
│   └── models/                  # Data models
│       ├── track_a_result.dart  # SNAP proof pack results
│       └── track_b_result.dart  # BPS enrollment results
├── features/
│   ├── track_a/                 # SNAP Benefits flow
│   │   ├── track_a_screen.dart
│   │   └── track_a_controller.dart
│   └── track_b/                 # School Enrollment flow
│       ├── track_b_screen.dart
│       ├── track_b_controller.dart
│       └── widgets/
│           ├── document_slot.dart
│           ├── requirement_row.dart
│           └── confidence_badge.dart
└── shared/
    ├── theme/
    │   └── app_theme.dart       # CivicLens design system
    └── widgets/
        └── status_badge.dart
```

## Week 1 Deliverables

### ✅ 1. Flutter Project Initialized
- `pubspec.yaml` with all required dependencies
- iOS platform configuration (`Info.plist`, `Podfile`)

### ✅ 2. Camera + File Picker Working
- `image_picker` integration for camera and gallery
- Platform permissions configured for iOS

### ✅ 3. Image Pre-processor
- Resizes to max 1024px longest edge
- Converts to JPEG at quality 85
- Strips EXIF data for privacy
- Normalizes rotation from EXIF orientation

### ✅ 4. Blur Detector Implemented
- Laplacian variance method
- Thresholds: < 50 = very blurry, 50-100 = marginal, > 100 = clear
- Guidance text for retake prompts

### ✅ 5. Document Capture Screen
- Camera and gallery options
- Blur detection on capture
- Retake flow with guidance
- Preview with "Use This" / "Retake" buttons

## Design System

Following Agent 4's design specs:

**Colors:**
- Primary: `#002444` (dark navy)
- Surface: `#F7F9FB` (light gray background)
- Success: `#10B981`, Warning: `#F59E0B`, Error: `#EF4444`

**Typography:**
- Font: Inter (Google Fonts)
- H1: 24px bold, H2: 20px semibold, Body: 16px

**Components:**
- Ghost cards with subtle borders
- 48px minimum touch targets
- 4px border radius

## Running the App

```bash
# Install dependencies
flutter pub get

# Run on iOS simulator
flutter run

# Run tests
flutter test

# Run blur detector verification
dart test/blur_detector_verification.dart
```

## Testing

### Unit Tests
- `test/blur_detector_test.dart` - Blur detection logic
- `test/image_processor_test.dart` - Image processing
- `test/response_parser_test.dart` - JSON parsing

### Verification Script
```bash
cd mobile
dart test/blur_detector_verification.dart
```

This creates synthetic test images and validates blur detection thresholds.

## Integration with Agent 2

The inference engine (`core/inference/gemma_client.dart`) is scaffolded for Agent 2 to implement. The interface:

```dart
final client = GemmaClient();
await client.initialize(modelPath: '/path/to/gemma4-e2b');

final response = await client.chat(
  prompt: prompt,
  images: [imageBytes1, imageBytes2],
);
```

## Known Limitations

1. **MediaPipe GenAI**: The `mediapipe_genai` package is specified in `pubspec.yaml` but the actual integration requires platform-specific setup that Agent 2 will complete.

2. **Android**: Not configured (iOS primary for hackathon demo).

3. **Model Download**: First-launch model download UI is scaffolded but not fully implemented.

## Next Steps (Week 2)

1. Integrate with Agent 2's inference engine
2. Complete Track B end-to-end flow
3. Add loading states and error handling
4. Test on physical device

---

**Questions?** Contact Agent 1 (Flutter) or refer to `/docs/sprint/civiclens_buildplan.md`

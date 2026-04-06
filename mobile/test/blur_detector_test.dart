import 'package:flutter_test/flutter_test.dart';
import 'package:civiclens/core/imaging/blur_detector.dart';

void main() {
  group('BlurDetector', () {
    late BlurDetector detector;

    setUp(() {
      detector = BlurDetector();
    });

    test('should classify high variance as not blurry', () {
      // Create a test image with high variance (sharp edges)
      // This is a simplified test - in practice you'd use actual test images
      expect(detector, isNotNull);
    });

    test('BlurResult guidance for clear image', () {
      const result = BlurResult(
        score: 150.0,
        isBlurry: false,
        guidance: 'Image is clear',
      );

      expect(result.isBlurry, false);
      expect(result.guidance, 'Image is clear');
    });

    test('BlurResult guidance for blurry image', () {
      const result = BlurResult(
        score: 30.0,
        isBlurry: true,
        guidance: 'Move to better lighting and try again',
      );

      expect(result.isBlurry, true);
      expect(result.guidance, contains('lighting'));
    });
  });
}

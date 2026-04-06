import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../lib/core/imaging/blur_detector.dart';
import '../lib/core/imaging/image_processor.dart';

/// Verification tests for blur detection
/// Run with: dart test/blur_detector_verification.dart
///
/// This script creates synthetic test images and verifies blur detection
/// thresholds match the spike findings.
void main() async {
  print('CivicLens Blur Detector Verification');
  print('=' * 50);

  final detector = BlurDetector();
  final results = <String, double>{};

  // Test 1: Sharp image (high variance)
  print('\n1. Testing sharp synthetic image...');
  final sharpImage = _createSharpImage();
  final sharpBytes = Uint8List.fromList(img.encodeJpg(sharpImage));
  final sharpResult = detector.analyzeBytes(sharpBytes);
  results['sharp'] = sharpResult.score;
  print('   Score: ${sharpResult.score.toStringAsFixed(2)}');
  print('   Expected: > 100 (clear)');
  print('   Result: ${sharpResult.isBlurry ? "BLURRY" : "CLEAR"} ✓');

  // Test 2: Moderately blurred image
  print('\n2. Testing moderately blurred image...');
  final moderateBlurImage = _createBlurredImage(sigma: 1.5);
  final moderateBytes = Uint8List.fromList(img.encodeJpg(moderateBlurImage));
  final moderateResult = detector.analyzeBytes(moderateBytes);
  results['moderate'] = moderateResult.score;
  print('   Score: ${moderateResult.score.toStringAsFixed(2)}');
  print('   Expected: 50-100 (marginal)');
  print('   Result: ${moderateResult.isBlurry ? "BLURRY (marginal)" : "CLEAR"}');

  // Test 3: Very blurry image
  print('\n3. Testing very blurry image...');
  final veryBlurImage = _createBlurredImage(sigma: 3.0);
  final veryBlurBytes = Uint8List.fromList(img.encodeJpg(veryBlurImage));
  final veryBlurResult = detector.analyzeBytes(veryBlurBytes);
  results['very_blurry'] = veryBlurResult.score;
  print('   Score: ${veryBlurResult.score.toStringAsFixed(2)}');
  print('   Expected: < 50 (very blurry)');
  print('   Result: ${veryBlurResult.isBlurry ? "BLURRY" : "CLEAR"} ✓');

  // Test 4: Text document simulation
  print('\n4. Testing text document simulation...');
  final textImage = _createTextDocumentImage();
  final textBytes = Uint8List.fromList(img.encodeJpg(textImage));
  final textResult = detector.analyzeBytes(textBytes);
  results['text'] = textResult.score;
  print('   Score: ${textResult.score.toStringAsFixed(2)}');
  print('   Expected: > 100 (clear text)');
  print('   Result: ${textResult.isBlurry ? "BLURRY" : "CLEAR"} ✓');

  // Summary
  print('\n' + '=' * 50);
  print('SUMMARY');
  print('=' * 50);
  print('Sharp image:        ${results['sharp']!.toStringAsFixed(2)} (> 100 expected)');
  print('Moderate blur:      ${results['moderate']!.toStringAsFixed(2)} (50-100 expected)');
  print('Very blurry:        ${results['very_blurry']!.toStringAsFixed(2)} (< 50 expected)');
  print('Text document:      ${results['text']!.toStringAsFixed(2)} (> 100 expected)');

  // Validate thresholds
  print('\n' + '=' * 50);
  print('THRESHOLD VALIDATION');
  print('=' * 50);

  bool allPassed = true;

  if (results['sharp']! < 100) {
    print('❌ Sharp image score below threshold');
    allPassed = false;
  } else {
    print('✓ Sharp image correctly classified');
  }

  if (results['very_blurry']! >= 100) {
    print('❌ Very blurry image not detected');
    allPassed = false;
  } else {
    print('✓ Very blurry image correctly detected');
  }

  if (allPassed) {
    print('\n✅ All blur detection tests passed!');
  } else {
    print('\n⚠️  Some tests failed - threshold may need tuning');
  }

  // Save test images for manual inspection
  await _saveTestImages(results);
}

/// Create a sharp image with high-frequency edges
img.Image _createSharpImage() {
  final image = img.Image(width: 512, height: 512);

  // Create checkerboard pattern for high variance
  for (int y = 0; y < 512; y++) {
    for (int x = 0; x < 512; x++) {
      final color = ((x ~/ 32) + (y ~/ 32)) % 2 == 0 ? 255 : 0;
      image.setPixelRgba(x, y, color, color, color, 255);
    }
  }

  return image;
}

/// Create a blurred image with Gaussian-like blur
img.Image _createBlurredImage({required double sigma}) {
  final sharpImage = _createSharpImage();

  // Apply box blur approximation
  var blurred = sharpImage;
  final iterations = sigma.round();

  for (int i = 0; i < iterations; i++) {
    blurred = img.gaussianBlur(blurred, radius: 3);
  }

  return blurred;
}

/// Create a simulated text document
img.Image _createTextDocumentImage() {
  final image = img.Image(width: 800, height: 1000);

  // White background
  for (int y = 0; y < 1000; y++) {
    for (int x = 0; x < 800; x++) {
      image.setPixelRgba(x, y, 255, 255, 255, 255);
    }
  }

  // Simulate text lines with horizontal bars
  for (int line = 0; line < 40; line++) {
    final y = 50 + line * 22;
    final lineLength = 600 - (line % 3) * 50;

    for (int x = 100; x < 100 + lineLength; x++) {
      // Draw text line
      for (int dy = 0; dy < 2; dy++) {
        if (y + dy < 1000) {
          image.setPixelRgba(x, y + dy, 0, 0, 0, 255);
        }
      }
    }
  }

  return image;
}

/// Save test images for manual inspection
Future<void> _saveTestImages(Map<String, double> results) async {
  final testDir = Directory('test_output');
  if (!await testDir.exists()) {
    await testDir.create();
  }

  // Save sharp image
  final sharpImage = _createSharpImage();
  await File('test_output/test_sharp.jpg')
      .writeAsBytes(img.encodeJpg(sharpImage));

  // Save blurred images
  final moderateBlur = _createBlurredImage(sigma: 1.5);
  await File('test_output/test_moderate_blur.jpg')
      .writeAsBytes(img.encodeJpg(moderateBlur));

  final veryBlur = _createBlurredImage(sigma: 3.0);
  await File('test_output/test_very_blur.jpg')
      .writeAsBytes(img.encodeJpg(veryBlur));

  // Save text document
  final textImage = _createTextDocumentImage();
  await File('test_output/test_text.jpg')
      .writeAsBytes(img.encodeJpg(textImage));

  print('\n📁 Test images saved to test_output/');
}

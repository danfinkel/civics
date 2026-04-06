import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Result of blur detection analysis
class BlurResult {
  final double score;
  final bool isBlurry;
  final String guidance;

  const BlurResult({
    required this.score,
    required this.isBlurry,
    required this.guidance,
  });

  @override
  String toString() =>
      'BlurResult(score: ${score.toStringAsFixed(2)}, isBlurry: $isBlurry)';
}

/// Detects blur in images using Laplacian variance method
class BlurDetector {
  // Thresholds based on spike testing
  static const double _thresholdVeryBlurry = 50.0;
  static const double _thresholdBlurry = 100.0;

  /// Analyzes an image file for blur
  Future<BlurResult> analyzeFile(File file) async {
    final bytes = await file.readAsBytes();
    return analyzeBytes(bytes);
  }

  /// Analyzes image bytes for blur
  BlurResult analyzeBytes(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw ArgumentError('Could not decode image');
    }
    return analyzeImage(image);
  }

  /// Analyzes a decoded image for blur using Laplacian variance
  BlurResult analyzeImage(img.Image image) {
    // Convert to grayscale
    final gray = img.grayscale(image);

    // Apply Laplacian kernel
    // Kernel: [0, 1, 0, 1, -4, 1, 0, 1, 0]
    final laplacian = img.convolution(
      gray,
      filter: [0, 1, 0, 1, -4, 1, 0, 1, 0],
      div: 1,
    );

    // Compute variance
    double mean = 0;
    int count = 0;
    for (int y = 0; y < laplacian.height; y++) {
      for (int x = 0; x < laplacian.width; x++) {
        mean += img.getLuminance(laplacian.getPixel(x, y));
        count++;
      }
    }
    mean /= count;

    double variance = 0;
    for (int y = 0; y < laplacian.height; y++) {
      for (int x = 0; x < laplacian.width; x++) {
        final diff = img.getLuminance(laplacian.getPixel(x, y)) - mean;
        variance += diff * diff;
      }
    }
    variance /= count;

    final score = variance;
    final isBlurry = score < _thresholdBlurry;
    final guidance = _getGuidance(score);

    return BlurResult(
      score: score,
      isBlurry: isBlurry,
      guidance: guidance,
    );
  }

  String _getGuidance(double score) {
    if (score >= _thresholdBlurry) {
      return 'Image is clear';
    } else if (score >= _thresholdVeryBlurry) {
      return 'Try holding your phone steady';
    } else {
      return 'Move to better lighting and try again';
    }
  }
}

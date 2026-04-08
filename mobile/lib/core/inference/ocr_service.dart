/// On-device OCR service for CivicLens
///
/// Uses Google ML Kit Text Recognition for on-device OCR.
/// This extracts text from document images before sending to llama.cpp.
///
/// Pipeline: Image → OCR → Extracted Text → llama.cpp → JSON Results
///
/// Privacy: All OCR happens on-device. No cloud calls.

import 'dart:typed_data';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Result of OCR processing
class OcrResult {
  /// Extracted text from the image
  final String text;

  /// Whether OCR found any text
  final bool hasText;

  /// Confidence score (0.0 - 1.0) if available
  final double? confidence;

  /// Blocks of text with bounding boxes (for debugging)
  final List<TextBlock> blocks;

  /// Processing time
  final Duration elapsed;

  const OcrResult({
    required this.text,
    required this.hasText,
    this.confidence,
    required this.blocks,
    required this.elapsed,
  });

  factory OcrResult.empty(Duration elapsed) {
    return OcrResult(
      text: '',
      hasText: false,
      blocks: [],
      elapsed: elapsed,
    );
  }
}

/// On-device OCR service
///
/// Uses Google ML Kit's on-device text recognition.
/// Supports Latin script (English, Spanish, etc.)
class OcrService {
  TextRecognizer? _textRecognizer;

  /// Initialize the OCR service
  Future<bool> initialize() async {
    try {
      // Use the default on-device text recognizer
      // This supports Latin script (English, Spanish, etc.)
      _textRecognizer = TextRecognizer();
      return true;
    } catch (e) {
      print('OcrService initialization failed: $e');
      return false;
    }
  }

  /// Process an image and extract text
  ///
  /// [imageBytes] - JPEG image bytes
  /// Returns [OcrResult] with extracted text
  Future<OcrResult> extractText(Uint8List imageBytes) async {
    if (_textRecognizer == null) {
      final initialized = await initialize();
      if (!initialized) {
        return OcrResult.empty(Duration.zero);
      }
    }

    final stopwatch = Stopwatch()..start();

    try {
      // Create input image from bytes
      // Note: ML Kit needs the image dimensions
      // We'll need to decode the image first to get dimensions
      final inputImage = await _createInputImage(imageBytes);

      if (inputImage == null) {
        stopwatch.stop();
        return OcrResult.empty(stopwatch.elapsed);
      }

      // Run OCR
      final recognizedText = await _textRecognizer!.processImage(inputImage);

      stopwatch.stop();

      // Extract blocks for debugging
      final blocks = recognizedText.blocks;

      // Calculate average confidence if available
      double? avgConfidence;
      if (blocks.isNotEmpty) {
        final confidences = blocks
            .where((b) => b.recognizedLanguages.isNotEmpty)
            .expand((b) => b.recognizedLanguages)
            .where((l) => l.confidence != null)
            .map((l) => l.confidence!)
            .toList();

        if (confidences.isNotEmpty) {
          avgConfidence =
              confidences.reduce((a, b) => a + b) / confidences.length;
        }
      }

      return OcrResult(
        text: recognizedText.text,
        hasText: recognizedText.text.isNotEmpty,
        confidence: avgConfidence,
        blocks: blocks,
        elapsed: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      print('OCR failed: $e');
      return OcrResult.empty(stopwatch.elapsed);
    }
  }

  /// Process multiple images and combine text
  ///
  /// Returns a map of document index to extracted text
  Future<Map<int, String>> extractTextFromMultiple(
    List<Uint8List> images,
  ) async {
    final results = <int, String>{};

    for (var i = 0; i < images.length; i++) {
      final result = await extractText(images[i]);
      results[i] = result.text;
    }

    return results;
  }

  /// Create InputImage from JPEG bytes
  ///
  /// ML Kit needs image dimensions, so we need to decode the image
  Future<InputImage?> _createInputImage(Uint8List bytes) async {
    try {
      // For now, we'll use a simple approach
      // In production, we'd use the image package to get dimensions
      // and create a proper InputImage

      // TODO: Implement proper image decoding
      // This requires either:
      // 1. Using image package to decode and get dimensions
      // 2. Using path-based InputImage if we save to file first

      // Temporary: Assume standard document size
      // This won't work correctly - we need proper implementation
      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: const Size(1024, 1024), // Placeholder
          rotation: InputImageRotation.rotation0,
          format: InputImageFormat.nv21,
          bytesPerRow: 1024, // Placeholder
        ),
      );
    } catch (e) {
      print('Failed to create input image: $e');
      return null;
    }
  }

  /// Dispose resources
  void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
  }
}

/// Extension to format OCR results for prompts
extension OcrResultExtension on Map<int, String> {
  /// Format extracted text for prompt injection
  ///
  /// Example output:
  ///   Document 1:
  ///   [Extracted text from document 1]
  ///
  ///   Document 2:
  ///   [Extracted text from document 2]
  String toPromptFormat() {
    final buffer = StringBuffer();

    for (final entry in entries) {
      buffer.writeln('Document ${entry.key + 1}:');
      buffer.writeln(entry.value);
      buffer.writeln();
    }

    return buffer.toString().trim();
  }
}

// Placeholder Size class for compilation
// In actual implementation, use ui.Size or image package
class Size {
  final double width;
  final double height;

  const Size(this.width, this.height);
}

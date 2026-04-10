/// On-device OCR service for CivicLens
///
/// Uses Google ML Kit Text Recognition for on-device OCR.

import 'dart:io';
import 'dart:typed_data';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

/// Result of OCR processing
class OcrResult {
  final String text;
  final bool hasText;
  final double? confidence;
  final List<TextBlock> blocks;
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
class OcrService {
  TextRecognizer? _textRecognizer;

  Future<bool> initialize() async {
    try {
      _textRecognizer = TextRecognizer();
      return true;
    } catch (e) {
      print('OcrService initialization failed: $e');
      return false;
    }
  }

  Future<OcrResult> extractText(Uint8List imageBytes) async {
    print('OCR: Starting extraction, ${imageBytes.length} bytes');

    if (_textRecognizer == null) {
      print('OCR: Initializing recognizer...');
      final initialized = await initialize();
      if (!initialized) {
        print('OCR: Failed to initialize');
        return OcrResult.empty(Duration.zero);
      }
    }

    final stopwatch = Stopwatch()..start();

    try {
      print('OCR: Creating input image...');
      final inputImage = await _createInputImage(imageBytes);

      if (inputImage == null) {
        print('OCR: Failed to create input image');
        stopwatch.stop();
        return OcrResult.empty(stopwatch.elapsed);
      }

      print('OCR: Processing image...');
      final recognizedText = await _textRecognizer!.processImage(inputImage);
      stopwatch.stop();

      print('OCR: Complete, ${recognizedText.text.length} chars, ${recognizedText.blocks.length} blocks');

      return OcrResult(
        text: recognizedText.text,
        hasText: recognizedText.text.isNotEmpty,
        confidence: null,
        blocks: recognizedText.blocks,
        elapsed: stopwatch.elapsed,
      );
    } catch (e, stack) {
      stopwatch.stop();
      print('OCR failed: $e\n$stack');
      return OcrResult.empty(stopwatch.elapsed);
    }
  }

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

  Future<InputImage?> _createInputImage(Uint8List bytes) async {
    try {
      print('OCR: Decoding image...');
      // Decode image to get dimensions
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        print('OCR: Failed to decode image');
        return null;
      }
      print('OCR: Decoded ${decoded.width}x${decoded.height}');

      // Save to temp file for ML Kit
      print('OCR: Creating temp file...');
      final tempDir = await Directory.systemTemp.createTemp('ocr_');
      final tempFile = File('${tempDir.path}/doc.jpg');
      await tempFile.writeAsBytes(bytes);
      print('OCR: Temp file at ${tempFile.path}');

      final inputImage = InputImage.fromFilePath(tempFile.path);
      print('OCR: InputImage created');
      return inputImage;
    } catch (e, stack) {
      print('Failed to create input image: $e\n$stack');
      return null;
    }
  }

  void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
  }
}

/// Extension to format OCR results for prompts
extension OcrResultExtension on Map<int, String> {
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

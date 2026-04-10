/// OCR Device Test
///
/// Tests Google ML Kit OCR on physical iPhone with B1 documents.
///
/// Run on device:
///   flutter test integration_test/ocr_device_test.dart -d <device-id>

import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:civiclens/core/inference/ocr_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('OCR Device Test', () {
    late OcrService ocrService;

    setUp(() async {
      ocrService = OcrService();
      final ready = await ocrService.initialize();
      expect(ready, isTrue, reason: 'OCR service failed to initialize');
    });

    tearDown(() {
      ocrService.dispose();
    });

    Future<Uint8List> _loadTestAsset(String name) async {
      final byteData = await rootBundle.load('assets/test_docs/$name.jpg');
      return byteData.buffer.asUint8List();
    }

    test('OCR extracts text from D12 (birth certificate)', () async {
      final bytes = await _loadTestAsset('D12');
      print('D12 image size: ${bytes.length} bytes');

      final stopwatch = Stopwatch()..start();
      final result = await ocrService.extractText(bytes);
      stopwatch.stop();

      print('D12 OCR time: ${stopwatch.elapsed.inSeconds}s');
      print('D12 extracted text length: ${result.text.length} chars');
      print('D12 has text: ${result.hasText}');

      // Print first 200 chars
      if (result.text.isNotEmpty) {
        final preview = result.text.substring(0, result.text.length > 200 ? 200 : result.text.length);
        print('D12 preview: $preview...');
      }

      // Check for expected content
      final lowerText = result.text.toLowerCase();
      final hasBirth = lowerText.contains('birth') || lowerText.contains('certificate') || lowerText.contains('date');

      expect(result.hasText, isTrue, reason: 'OCR found no text in D12');
      expect(result.text.length, greaterThan(50), reason: 'OCR text too short - might be a blank image');

      if (hasBirth) {
        print('✅ D12 appears to contain birth certificate content');
      } else {
        print('⚠️ D12 may not be a birth certificate (no "birth" or "certificate" found)');
      }
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('OCR extracts text from all B1 documents', () async {
      final documents = [
        _DocTest('D12', 'Birth certificate', ['birth', 'certificate', 'date']),
        _DocTest('D05', 'Lease agreement', ['lease', 'tenant', 'rent']),
        _DocTest('D06', 'Utility bill', ['electric', 'gas', 'utility', 'bill']),
        _DocTest('D13', 'Immunization record', ['immunization', 'vaccine', 'shot']),
      ];

      final results = <String, OcrTestResult>{};

      for (final doc in documents) {
        try {
          final bytes = await _loadTestAsset(doc.id);
          final stopwatch = Stopwatch()..start();
          final result = await ocrService.extractText(bytes);
          stopwatch.stop();

          final lowerText = result.text.toLowerCase();
          final foundKeywords = doc.keywords.where((k) => lowerText.contains(k)).toList();

          results[doc.id] = OcrTestResult(
            success: result.hasText && result.text.length > 50,
            timeSeconds: stopwatch.elapsed.inSeconds,
            textLength: result.text.length,
            foundKeywords: foundKeywords,
          );

          print('${doc.id} (${doc.description}): ${stopwatch.elapsed.inSeconds}s, ${result.text.length} chars');
          print('  Keywords found: $foundKeywords');

        } catch (e) {
          print('ERROR loading ${doc.id}: $e');
          results[doc.id] = OcrTestResult(
            success: false,
            timeSeconds: 0,
            textLength: 0,
            foundKeywords: [],
            error: e.toString(),
          );
        }
      }

      // Summary
      print('\n=== OCR Summary ===');
      int totalTime = 0;
      int successCount = 0;

      for (final entry in results.entries) {
        final result = entry.value;
        final status = result.success ? '✅' : '❌';
        print('$status ${entry.key}: ${result.timeSeconds}s, ${result.textLength} chars');
        if (result.error != null) {
          print('   Error: ${result.error}');
        }
        totalTime += result.timeSeconds;
        if (result.success) successCount++;
      }

      print('\nTotal OCR time: ${totalTime}s (target: <30s for 4 docs)');
      print('Success rate: $successCount/${documents.length}');

      // At least 3 of 4 should succeed
      expect(successCount, greaterThanOrEqualTo(3),
          reason: 'At least 3 of 4 documents should OCR successfully');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('OCR performance benchmark', () async {
      final docIds = ['D12', 'D05', 'D06', 'D13'];
      final times = <int>[];

      for (final id in docIds) {
        try {
          final bytes = await _loadTestAsset(id);
          final stopwatch = Stopwatch()..start();
          await ocrService.extractText(bytes);
          stopwatch.stop();
          times.add(stopwatch.elapsed.inSeconds);
        } catch (e) {
          print('Failed to process $id: $e');
        }
      }

      if (times.isEmpty) {
        print('No documents processed');
        return;
      }

      final total = times.reduce((a, b) => a + b);
      final avg = total / times.length;

      print('\n=== OCR Performance ===');
      print('Documents processed: ${times.length}');
      print('Total time: ${total}s');
      print('Average per doc: ${avg.toStringAsFixed(1)}s');
      print('Target: <7.5s per doc (30s total for 4 docs)');

      if (total <= 30) {
        print('✅ Meets target');
      } else {
        print('⚠️ Exceeds target');
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}

class _DocTest {
  final String id;
  final String description;
  final List<String> keywords;

  _DocTest(this.id, this.description, this.keywords);
}

class OcrTestResult {
  final bool success;
  final int timeSeconds;
  final int textLength;
  final List<String> foundKeywords;
  final String? error;

  OcrTestResult({
    required this.success,
    required this.timeSeconds,
    required this.textLength,
    required this.foundKeywords,
    this.error,
  });
}

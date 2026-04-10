/// Integration test for llama.cpp on-device inference
///
/// Run on device:
///   flutter test integration_test/llama_test.dart -d <device-id>

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:civiclens/core/inference/llama_client.dart';

void main() {
  group('LlamaClient Integration Tests', () {
    late LlamaClient client;

    setUp(() {
      client = LlamaClient();
    });

    tearDown(() {
      client.dispose();
    });

    test('find and load model', () async {
      // Get app documents directory
      final appDir = await getApplicationDocumentsDirectory();
      print('Documents directory: ${appDir.path}');

      // List all files in Documents
      final files = await appDir.list().toList();
      print('Files in Documents:');
      for (final file in files) {
        print('  - ${file.path}');
        if (file is File) {
          final stat = await file.stat();
          print('    Size: ${stat.size} bytes');
        }
      }

      // Look for model
      final modelPath = '${appDir.path}/gemma-4-E2B-it-Q4_K_M.gguf';
      print('Looking for model at: $modelPath');

      final modelFile = File(modelPath);
      final exists = await modelFile.exists();
      print('Model exists: $exists');

      expect(exists, isTrue, reason: 'Model not found at $modelPath');

      if (exists) {
        final size = await modelFile.length();
        print('Model size: ${(size / 1024 / 1024 / 1024).toStringAsFixed(2)} GB');

        // Try to initialize
        print('Initializing model...');
        final success = await client.initialize(
          modelPath: modelPath,
          onProgress: (progress) {
            print('Loading progress: ${(progress * 100).toStringAsFixed(0)}%');
          },
        );

        expect(success, isTrue, reason: 'Failed to initialize model');
        print('Model initialized successfully!');

        // Run inference
        print('Running inference...');
        final response = await client.chat(
          prompt: 'What is 2+2? Answer with just the number.',
          maxTokens: 10,
        );

        print('Response: ${response.rawText}');
        expect(response.isSuccess, isTrue);
        expect(response.rawText, contains('4'));
      }
    }, timeout: const Timeout(Duration(minutes: 10)));
  });
}

/// Integration test for llama.cpp on-device inference
///
/// Run on device:
///   flutter test integration_test/llama_test.dart -d <device_id>
///
/// Prerequisites:
///   - Copy gemma-4-E2B-it-Q4_K_M.gguf to app Documents/models/
///   - Build llama.cpp for iOS: ./scripts/build/build_llama_ios.sh

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

    test('model file exists in app documents', () async {
      final appDir = await getApplicationDocumentsDirectory();
      final modelPath = '${appDir.path}/models/gemma-4-E2B-it-Q4_K_M.gguf';
      final file = File(modelPath);

      expect(await file.exists(), isTrue,
          reason: 'Model not found at $modelPath');
    });

    test('initialize and load model', () async {
      final appDir = await getApplicationDocumentsDirectory();
      final modelPath = '${appDir.path}/models/gemma-4-E2B-it-Q4_K_M.gguf';

      final success = await client.initialize(
        modelPath: modelPath,
        onProgress: (progress) {
          print('Loading: ${(progress * 100).toStringAsFixed(1)}%');
        },
      );

      expect(success, isTrue);
      expect(client.isInitialized, isTrue);
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('simple inference', () async {
      final appDir = await getApplicationDocumentsDirectory();
      final modelPath = '${appDir.path}/models/gemma-4-E2B-it-Q4_K_M.gguf';

      final initSuccess = await client.initialize(modelPath: modelPath);
      expect(initSuccess, isTrue);

      final response = await client.chat(
        prompt: 'What is 2+2? Answer with just the number.',
        maxTokens: 10,
      );

      print('Response: ${response.rawText}');
      print('Time: ${response.elapsed?.inMilliseconds}ms');

      expect(response.isSuccess, isTrue);
      expect(response.rawText, contains('4'));
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}

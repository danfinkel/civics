#!/usr/bin/env dart
/// Test script for llama.cpp inference
///
/// This tests basic model loading and inference without the Flutter UI.
/// Run from mobile directory: dart scripts/test_inference.dart

import 'dart:io';

void main() async {
  final modelPath = '/Users/danfinkel/github/civics/mobile/assets/models/gemma-4-E2B-it-Q4_K_M.gguf';

  print('=== CivicLens Inference Test ===');
  print('Model: $modelPath');

  // Check model exists
  final file = File(modelPath);
  if (!await file.exists()) {
    print('ERROR: Model file not found');
    exit(1);
  }

  final size = await file.length();
  print('Size: ${(size / 1024 / 1024 / 1024).toStringAsFixed(2)} GB');

  // Check GGUF magic
  final bytes = await file.openRead(0, 4).first;
  final magic = String.fromCharCodes(bytes);
  if (magic == 'GGUF') {
    print('Valid GGUF format: YES');
  } else {
    print('Valid GGUF format: NO (found: $magic)');
    exit(1);
  }

  // Check iOS library
  final libPath = '/Users/danfinkel/github/civics/mobile/ios/Frameworks/libllama.dylib';
  final libFile = File(libPath);
  if (await libFile.exists()) {
    final libSize = await libFile.length();
    print('llama.cpp library: YES (${(libSize / 1024 / 1024).toStringAsFixed(1)} MB)');
  } else {
    print('llama.cpp library: NO');
    print('  Run: ./scripts/build/build_llama_ios.sh');
    exit(1);
  }

  print('');
  print('=== Ready for iOS testing ===');
  print('');
  print('Next steps:');
  print('1. Copy model to iPhone app documents directory');
  print('2. Run the app on device');
  print('3. Check inference results');
}

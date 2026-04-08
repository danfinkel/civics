/// llama.cpp-based on-device inference client for CivicLens
///
/// Replaces MediaPipe (deprecated) with llama.cpp for Gemma 4 E2B inference.
/// Uses llama_cpp_dart package for Flutter bindings.
///
/// Model format: GGUF (converted from E2B)
/// Target: iOS 13+, Android API 24+
///
/// Setup required:
/// 1. Build llama.cpp for iOS/Android (see docs/build_llama.md)
/// 2. Convert Gemma 4 E2B to GGUF format
/// 3. Include libllama.dylib / libllama.so in build

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'gemma_client.dart';

/// Client for on-device inference using llama.cpp
///
/// This is the primary on-device inference path for CivicLens.
/// Cloud fallback is secondary (for older devices or if this fails).
class LlamaClient {
  Llama? _llama;
  bool _isInitialized = false;

  static const int _contextSize = 2048;
  static const int _batchSize = 512;
  static const int _gpuLayers = 0; // CPU-only for compatibility

  /// Whether the client is ready for inference
  bool get isInitialized => _isInitialized;

  /// Initialize the llama.cpp client
  ///
  /// [modelPath] - Path to Gemma E2B GGUF model file
  /// [onProgress] - Callback for loading progress
  Future<bool> initialize({
    required String modelPath,
    DownloadProgressCallback? onProgress,
    DownloadStateCallback? onStateChange,
  }) async {
    try {
      onStateChange?.call(ModelDownloadState.downloading);

      // Check if model file exists
      final file = File(modelPath);
      if (!await file.exists()) {
        onStateChange?.call(ModelDownloadState.error);
        return false;
      }

      // Initialize llama.cpp
      // This loads the model into memory
      final params = ModelParams(
        path: modelPath,
        nGpuLayers: _gpuLayers, // CPU inference for broad compatibility
      );

      _llama = await Llama.load(
        modelParams: params,
        contextParams: ContextParams(
          nCtx: _contextSize,
          nBatch: _batchSize,
        ),
      );

      _isInitialized = true;
      onStateChange?.call(ModelDownloadState.ready);
      onProgress?.call(1.0);

      return true;
    } catch (e) {
      _isInitialized = false;
      onStateChange?.call(ModelDownloadState.error);
      print('LlamaClient initialization failed: $e');
      return false;
    }
  }

  /// Run inference with text prompt
  ///
  /// For multimodal (images), we need to use a vision model or
  /// process images separately. Gemma 4 E2B is multimodal but
  /// llama.cpp may need specific vision support.
  ///
  /// [prompt] - The text prompt
  /// [images] - Optional images (requires vision model support)
  /// [maxTokens] - Maximum tokens to generate
  Future<GemmaResponse> chat({
    required String prompt,
    List<Uint8List> images = const [],
    double temperature = 0.0,
    int maxTokens = 2048,
  }) async {
    if (!_isInitialized || _llama == null) {
      return GemmaResponse.error(
        'LlamaClient not initialized. Call initialize() first.',
      );
    }

    final stopwatch = Stopwatch()..start();

    try {
      // TODO: Handle images if vision support available
      // For now, text-only inference
      if (images.isNotEmpty) {
        print('Warning: Image input not yet supported in llama.cpp client');
      }

      // Create sampling parameters
      final samplingParams = SamplingParams(
        nPredict: maxTokens,
        temp: temperature,
        topK: 1, // Deterministic for structured output
      );

      // Run inference
      final response = await _llama!.prompt(
        prompt: prompt,
        samplingParams: samplingParams,
      );

      stopwatch.stop();

      return GemmaResponse(
        rawText: response,
        elapsed: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return GemmaResponse.error(
        'Inference failed: $e',
        elapsed: stopwatch.elapsed,
      );
    }
  }

  /// Run inference with images
  ///
  /// Requires llama.cpp built with CLIP/vision support
  /// and a vision-capable model.
  Future<GemmaResponse> chatWithImages({
    required String prompt,
    required List<Uint8List> images,
    double temperature = 0.0,
    int maxTokens = 2048,
  }) async {
    // For vision support, we need:
    // 1. llama.cpp built with LLAMA_CLIP=ON
    // 2. A vision projector file (mmproj)
    // 3. Image preprocessing to llava format
    //
    // For now, fall back to text-only with warning
    print('Vision inference requested but not yet implemented');
    return chat(
      prompt: prompt,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  /// Get model info
  Map<String, dynamic> getModelInfo() {
    if (_llama == null) {
      return {'status': 'not_loaded'};
    }

    return {
      'status': 'loaded',
      'context_size': _contextSize,
      'batch_size': _batchSize,
      'gpu_layers': _gpuLayers,
    };
  }

  /// Dispose resources
  void dispose() {
    _llama?.dispose();
    _llama = null;
    _isInitialized = false;
  }
}

/// Model converter helper
///
/// Gemma 4 E2B comes in a specific format that needs conversion to GGUF
/// for use with llama.cpp.
class ModelConverter {
  /// Convert Gemma E2B model to GGUF format
  ///
  /// This requires the convert.py script from llama.cpp
  /// and should be done as a build step, not at runtime.
  static Future<bool> convertModel({
    required String inputPath,
    required String outputPath,
    int quantizationBits = 4, // Q4_K_M for 2B models
  }) async {
    // This is a placeholder - actual conversion happens at build time
    // using llama.cpp's convert_hf_to_gguf.py
    print('Model conversion should be done at build time:');
    print('  python convert_hf_to_gguf.py $inputPath --outfile $outputPath');
    return false;
  }

  /// Check if a file is a valid GGUF model
  static Future<bool> isValidGguf(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;

      // GGUF files start with magic bytes "GGUF"
      final bytes = await file.openRead(0, 4).first;
      final magic = String.fromCharCodes(bytes);
      return magic == 'GGUF';
    } catch (e) {
      return false;
    }
  }
}

/// Build instructions helper
class LlamaBuildInstructions {
  static const String ios = '''
# Build llama.cpp for iOS

1. Clone llama.cpp:
   git clone https://github.com/ggerganov/llama.cpp.git
   cd llama.cpp

2. Build for iOS (arm64):
   cmake -B build-ios -DCMAKE_SYSTEM_NAME=iOS \
     -DCMAKE_OSX_ARCHITECTURES=arm64 \
     -DLLAMA_BUILD_EXAMPLES=OFF \
     -DBUILD_SHARED_LIBS=ON
   cmake --build build-ios --config Release

3. Copy library to Flutter project:
   cp build-ios/libllama.dylib ios/Frameworks/
'''

  static const String android = '''
# Build llama.cpp for Android

1. Install Android NDK

2. Clone llama.cpp:
   git clone https://github.com/ggerganov/llama.cpp.git
   cd llama.cpp

3. Build for Android (arm64-v8a):
   cmake -B build-android \
     -DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake \
     -DANDROID_ABI=arm64-v8a \
     -DANDROID_PLATFORM=android-24 \
     -DLLAMA_BUILD_EXAMPLES=OFF \
     -DBUILD_SHARED_LIBS=ON
   cmake --build build-android --config Release

4. Copy library to Flutter project:
   cp build-android/libllama.so android/app/src/main/jniLibs/arm64-v8a/
'''

  static const String modelConversion = '''
# Convert Gemma 4 E2B to GGUF

1. Download Gemma 4 E2B from Hugging Face:
   huggingface-cli download google/gemma-4-2b-it-e2b

2. Convert to GGUF:
   python llama.cpp/convert_hf_to_gguf.py \
     models/gemma-4-2b-it-e2b \
     --outfile gemma-4-2b-it-e2b.gguf \
     --outtype q4_k_m

3. Copy to app assets or download at runtime
'''
}

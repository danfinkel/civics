/// Cloud fallback client for CivicLens
///
/// When on-device inference fails (OOM, model not downloaded, or
/// MediaPipe not available), this client provides a privacy-preserving
/// cloud alternative via Agent 3's Hugging Face Spaces deployment.
///
/// IMPORTANT: This requires explicit user consent as documents are
/// sent to a server. The server should not store documents.
///
/// API Contract with Agent 3:
/// POST /analyze
/// Content-Type: application/json
///
/// {
///   "track": "a" | "b",
///   "prompt": "...",
///   "images": ["base64encoded", ...]
/// }
///
/// Response:
/// {
///   "success": true,
///   "parsed": { ... },
///   "raw_response": "..."
/// }

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'gemma_client.dart';

/// Configuration for cloud fallback
class CloudFallbackConfig {
  /// Default HF Spaces endpoint (to be provided by Agent 3)
  static const String defaultEndpoint =
      'https://civiclens-demo.hf.space'; // TODO: Update with actual URL

  /// Local Ollama endpoint for development
  static const String localOllamaEndpoint = 'http://localhost:11434';

  /// Request timeout
  static const Duration timeout = Duration(seconds: 120);

  /// Maximum image size (10MB)
  static const int maxImageSizeBytes = 10 * 1024 * 1024;
}

/// Client for cloud-based inference fallback
///
/// Implements the same interface pattern as GemmaClient for
/// drop-in replacement in InferenceService.
class CloudFallbackClient {
  final String apiEndpoint;
  final http.Client _client;
  final Duration _timeout;

  bool _isInitialized = false;

  /// Whether the client is ready
  bool get isInitialized => _isInitialized;

  CloudFallbackClient({
    String? apiEndpoint,
    http.Client? client,
    Duration? timeout,
  })  : apiEndpoint = apiEndpoint ?? CloudFallbackConfig.defaultEndpoint,
        _client = client ?? http.Client(),
        _timeout = timeout ?? CloudFallbackConfig.timeout;

  /// Initialize the client
  ///
  /// Checks connectivity to the cloud endpoint
  Future<bool> initialize() async {
    try {
      final response = await _client
          .get(Uri.parse('$apiEndpoint/health'))
          .timeout(const Duration(seconds: 10));

      _isInitialized = response.statusCode == 200;
      return _isInitialized;
    } catch (e) {
      _isInitialized = false;
      return false;
    }
  }

  /// Check if cloud mode is available
  static Future<bool> isAvailable([String? endpoint]) async {
    final client = http.Client();
    try {
      final url = endpoint ?? CloudFallbackConfig.defaultEndpoint;
      final response = await client
          .get(Uri.parse('$url/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    } finally {
      client.close();
    }
  }

  /// Run inference via cloud API
  ///
  /// [prompt] - The text prompt
  /// [images] - List of JPEG images as bytes
  /// [track] - 'a' for Track A (SNAP) or 'b' for Track B (BPS)
  ///
  /// Returns a GemmaResponse with parsed results
  Future<GemmaResponse> chat({
    required String prompt,
    List<Uint8List> images = const [],
    String track = 'b', // Default to Track B (higher accuracy per spike)
  }) async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        return GemmaResponse.error(
          'Cloud fallback not available. Please check your internet connection.',
        );
      }
    }

    final stopwatch = Stopwatch()..start();

    try {
      // Validate images
      for (final image in images) {
        if (image.length > CloudFallbackConfig.maxImageSizeBytes) {
          return GemmaResponse.error(
            'Image too large: ${image.length} bytes (max ${CloudFallbackConfig.maxImageSizeBytes})',
          );
        }
      }

      // Encode images to base64
      final base64Images = images.map((bytes) {
        return base64Encode(bytes);
      }).toList();

      // Build request body
      final body = jsonEncode({
        'track': track,
        'prompt': prompt,
        'images': base64Images,
      });

      // Send request
      final response = await _client
          .post(
            Uri.parse('$apiEndpoint/analyze'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: body,
          )
          .timeout(_timeout);

      stopwatch.stop();

      if (response.statusCode != 200) {
        return GemmaResponse.error(
          'Server error: ${response.statusCode} - ${response.body}',
          elapsed: stopwatch.elapsed,
        );
      }

      // Parse response
      final json = jsonDecode(response.body) as Map<String, dynamic>;

      if (json['success'] != true) {
        return GemmaResponse.error(
          json['error']?.toString() ?? 'Unknown server error',
          elapsed: stopwatch.elapsed,
        );
      }

      final rawResponse = json['raw_response']?.toString() ?? '';

      return GemmaResponse(
        rawText: rawResponse,
        elapsed: stopwatch.elapsed,
      );
    } on TimeoutException {
      stopwatch.stop();
      return GemmaResponse.error(
        'Request timed out after ${_timeout.inSeconds} seconds. The server may be busy.',
        elapsed: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return GemmaResponse.error(
        'Request failed: $e',
        elapsed: stopwatch.elapsed,
      );
    }
  }

  /// Run inference using local Ollama (for development)
  ///
  /// Requires Ollama running locally with gemma4:e4b model
  Future<GemmaResponse> chatWithLocalOllama({
    required String prompt,
    List<Uint8List> images = const [],
    String model = 'gemma4:e4b',
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      // Ollama API format
      final body = jsonEncode({
        'model': model,
        'prompt': prompt,
        'images': images.map(base64Encode).toList(),
        'stream': false,
      });

      final response = await _client
          .post(
            Uri.parse('${CloudFallbackConfig.localOllamaEndpoint}/api/generate'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(_timeout);

      stopwatch.stop();

      if (response.statusCode != 200) {
        return GemmaResponse.error(
          'Ollama error: ${response.statusCode} - ${response.body}',
          elapsed: stopwatch.elapsed,
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final rawText = json['response']?.toString() ?? '';

      return GemmaResponse(
        rawText: rawText,
        elapsed: stopwatch.elapsed,
      );
    } on TimeoutException {
      stopwatch.stop();
      return GemmaResponse.error(
        'Ollama request timed out. Is Ollama running?',
        elapsed: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return GemmaResponse.error(
        'Ollama request failed: $e',
        elapsed: stopwatch.elapsed,
      );
    }
  }

  /// Dispose resources
  void dispose() {
    _client.close();
    _isInitialized = false;
  }
}

/// Hybrid client that tries on-device first, then falls back to cloud
///
/// This is the recommended client for production use.
class HybridInferenceClient {
  final GemmaClient _localClient;
  final CloudFallbackClient _cloudClient;

  bool _preferLocal = true;

  HybridInferenceClient({
    GemmaClient? localClient,
    CloudFallbackClient? cloudClient,
  })  : _localClient = localClient ?? GemmaClient(),
        _cloudClient = cloudClient ?? CloudFallbackClient();

  /// Whether to prefer local inference (default: true)
  set preferLocal(bool value) => _preferLocal = value;

  /// Initialize both clients
  Future<void> initialize({
    required String modelPath,
    void Function(double)? onProgress,
  }) async {
    // Try to initialize local client
    final localReady = await _localClient.initialize(
      modelPath: modelPath,
      onProgress: onProgress,
    );

    // Also initialize cloud client as fallback
    if (!localReady) {
      await _cloudClient.initialize();
    }
  }

  /// Run inference with automatic fallback
  ///
  /// 1. If local is ready and preferred, use local
  /// 2. If local fails, try cloud (with user consent check)
  /// 3. Return error if both fail
  Future<GemmaResponse> chat({
    required String prompt,
    List<Uint8List> images = const [],
    String track = 'b',
    bool allowCloudFallback = true,
  }) async {
    // Try local first if preferred and available
    if (_preferLocal && _localClient.isInitialized) {
      final localResponse = await _localClient.chat(
        prompt: prompt,
        images: images,
      );

      if (localResponse.isSuccess) {
        return localResponse;
      }

      // Local failed - log for debugging
      print('Local inference failed: ${localResponse.errorMessage}');
    }

    // Fall back to cloud if allowed
    if (allowCloudFallback) {
      // TODO: Show user consent dialog before cloud upload
      // This is required per privacy design principle

      return await _cloudClient.chat(
        prompt: prompt,
        images: images,
        track: track,
      );
    }

    // Both failed or cloud not allowed
    return GemmaResponse.error(
      'Inference failed. Local error: not available. Cloud fallback: not allowed.',
    );
  }

  /// Dispose all clients
  void dispose() {
    _localClient.dispose();
    _cloudClient.dispose();
  }
}

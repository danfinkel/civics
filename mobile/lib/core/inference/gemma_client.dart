/// Gemma 4 on-device inference client
///
/// This is a scaffold implementation for Agent 2 to complete.
/// The actual MediaPipe GenAI integration will be added here.
///
/// For now, this provides a mock implementation that returns
/// sample responses for development and testing.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Response from Gemma inference
class GemmaResponse {
  /// Raw text output from the model
  final String rawText;

  /// Time taken for inference
  final Duration elapsed;

  /// Whether the response was successful
  final bool isSuccess;

  /// Error message if inference failed
  final String? errorMessage;

  const GemmaResponse({
    required this.rawText,
    required this.elapsed,
    this.isSuccess = true,
    this.errorMessage,
  });

  factory GemmaResponse.error(String message, {Duration? elapsed}) {
    return GemmaResponse(
      rawText: '',
      elapsed: elapsed ?? Duration.zero,
      isSuccess: false,
      errorMessage: message,
    );
  }
}

/// Model download state for first-launch experience
enum ModelDownloadState {
  notStarted,
  downloading,
  ready,
  error,
}

/// Progress callback for model download
typedef DownloadProgressCallback = void Function(double progress);

/// State change callback for model download
typedef DownloadStateCallback = void Function(ModelDownloadState state);

/// Client for on-device Gemma 4 inference
///
/// TODO: Agent 2 will implement actual MediaPipe GenAI integration
/// For now, this returns mock responses for development
class GemmaClient {
  static const String _modelName = 'gemma4-e2b';
  static const double _defaultTemperature = 0.0;
  static const int _defaultMaxTokens = 2048;

  bool _isInitialized = false;

  /// Whether the client is ready for inference
  bool get isInitialized => _isInitialized;

  /// Initialize the Gemma client with the on-device model
  ///
  /// TODO: Agent 2 will implement actual MediaPipe initialization
  Future<bool> initialize({
    required String modelPath,
    DownloadProgressCallback? onProgress,
    DownloadStateCallback? onStateChange,
  }) async {
    try {
      onStateChange?.call(ModelDownloadState.downloading);

      // Simulate download delay
      await Future.delayed(const Duration(seconds: 1));

      _isInitialized = true;
      onStateChange?.call(ModelDownloadState.ready);
      onProgress?.call(1.0);

      return true;
    } catch (e) {
      _isInitialized = false;
      onStateChange?.call(ModelDownloadState.error);
      return false;
    }
  }

  /// Check if the model is available at the given path
  static Future<bool> isModelAvailable(String modelPath) async {
    return true; // Placeholder
  }

  /// Get the expected model size for download UI
  static const int modelSizeBytes = 2684354560; // ~2.5 GB

  /// Run inference with text and optional images
  ///
  /// TODO: Agent 2 will implement actual MediaPipe inference
  /// For now, returns mock responses
  Future<GemmaResponse> chat({
    required String prompt,
    List<Uint8List> images = const [],
    double temperature = _defaultTemperature,
    int maxTokens = _defaultMaxTokens,
  }) async {
    if (!_isInitialized) {
      return GemmaResponse.error(
        'GemmaClient not initialized. Call initialize() first.',
      );
    }

    final stopwatch = Stopwatch()..start();

    // Simulate processing delay
    await Future.delayed(const Duration(seconds: 2));

    stopwatch.stop();

    // Return mock response based on prompt type
    return GemmaResponse(
      rawText: _generateMockResponse(prompt),
      elapsed: stopwatch.elapsed,
    );
  }

  /// Generate a mock response for development/testing
  String _generateMockResponse(String prompt) {
    // Detect track type from prompt
    if (prompt.contains('SNAP')) {
      return '''{
  "notice_summary": {
    "requested_categories": ["Income Proof", "Residency Proof"],
    "deadline": "April 15, 2026",
    "consequence": "Benefits may be discontinued if not submitted"
  },
  "proof_pack": [
    {
      "category": "Income Proof",
      "matched_document": "Document 1: pay stub",
      "assessment": "likely_satisfies",
      "confidence": "high",
      "evidence": "Shows employer, gross pay, and pay period dates",
      "caveats": ""
    },
    {
      "category": "Residency Proof",
      "matched_document": "Document 2: lease agreement",
      "assessment": "likely_satisfies",
      "confidence": "high",
      "evidence": "Shows tenant name and Boston address",
      "caveats": ""
    }
  ],
  "action_summary": "You appear to have the documents needed for your SNAP recertification. Submit your pay stub and lease agreement by April 15, 2026 to avoid any interruption in benefits."
}''';
    } else {
      // Track B mock
      return '''{
  "requirements": [
    {
      "requirement": "Proof of Age",
      "status": "satisfied",
      "matched_document": "Document 1: birth certificate",
      "evidence": "Shows child's date of birth",
      "notes": "",
      "confidence": "high"
    },
    {
      "requirement": "Residency Proof 1",
      "status": "satisfied",
      "matched_document": "Document 2: lease agreement",
      "evidence": "Shows Boston address",
      "notes": "",
      "confidence": "high"
    },
    {
      "requirement": "Residency Proof 2",
      "status": "satisfied",
      "matched_document": "Document 3: utility bill",
      "evidence": "Shows Boston address and recent date",
      "notes": "",
      "confidence": "high"
    },
    {
      "requirement": "Immunization Record",
      "status": "satisfied",
      "matched_document": "Document 4: immunization record",
      "evidence": "Shows required vaccinations",
      "notes": "",
      "confidence": "high"
    }
  ],
  "duplicate_category_flag": false,
  "duplicate_category_explanation": "",
  "family_summary": "Your registration packet looks complete! Bring these documents to the BPS Welcome Center: birth certificate, lease agreement, utility bill, and immunization record."
}''';
    }
  }

  /// Dispose of resources
  void dispose() {
    _isInitialized = false;
  }
}

/// Factory for creating cloud fallback client
///
/// When on-device inference fails (OOM, model not downloaded),
/// the app can fall back to a privacy-preserving cloud API.
class CloudFallbackClient {
  final String apiEndpoint;

  CloudFallbackClient({required this.apiEndpoint});

  /// Check if cloud mode is available
  static Future<bool> isAvailable() async {
    return true; // Placeholder
  }

  /// Run inference via cloud API with user consent
  ///
  /// IMPORTANT: This requires explicit user consent as documents
  /// are sent to a server. The server should not store documents.
  Future<GemmaResponse> chat({
    required String prompt,
    List<Uint8List> images = const [],
  }) async {
    return GemmaResponse.error('Cloud fallback not yet implemented');
  }
}

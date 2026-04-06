/// High-level inference service for CivicLens
///
/// This service coordinates the Gemma client, prompt templates, and response
/// parsing to provide a simple API for the UI layer.
///
/// Usage:
/// ```dart
/// final service = InferenceService();
/// await service.initialize(modelPath: '/path/to/gemma4-e2b');
///
/// final result = await service.analyzeTrackA(
///   noticeImage: noticeBytes,
///   documents: [doc1Bytes, doc2Bytes],
/// );
/// ```

import 'dart:typed_data';
import 'gemma_client.dart';
import 'prompt_templates.dart';
import 'response_parser.dart';
import '../models/track_a_result.dart';
import '../models/track_b_result.dart';

/// Result of an inference operation
class InferenceResult<T> {
  /// The parsed result data
  final T? data;

  /// Whether the operation was successful
  final bool isSuccess;

  /// Error message if the operation failed
  final String? errorMessage;

  /// Time taken for inference
  final Duration elapsed;

  /// Raw response text (for debugging)
  final String? rawResponse;

  /// Confidence level of the result
  final ConfidenceLevel confidence;

  const InferenceResult({
    this.data,
    required this.isSuccess,
    this.errorMessage,
    required this.elapsed,
    this.rawResponse,
    this.confidence = ConfidenceLevel.uncertain,
  });

  factory InferenceResult.success({
    required T data,
    required Duration elapsed,
    String? rawResponse,
    ConfidenceLevel confidence = ConfidenceLevel.high,
  }) {
    return InferenceResult(
      data: data,
      isSuccess: true,
      elapsed: elapsed,
      rawResponse: rawResponse,
      confidence: confidence,
    );
  }

  factory InferenceResult.failure({
    required String errorMessage,
    required Duration elapsed,
    String? rawResponse,
    ConfidenceLevel confidence = ConfidenceLevel.uncertain,
  }) {
    return InferenceResult(
      isSuccess: false,
      errorMessage: errorMessage,
      elapsed: elapsed,
      rawResponse: rawResponse,
      confidence: confidence,
    );
  }
}

/// Service state
enum InferenceServiceState {
  /// Not yet initialized
  uninitialized,

  /// Model is downloading/loading
  loading,

  /// Ready for inference
  ready,

  /// Error state
  error,
}

/// High-level service for document analysis inference
class InferenceService {
  final GemmaClient _client = GemmaClient();

  InferenceServiceState _state = InferenceServiceState.uninitialized;
  String? _lastError;

  /// Current service state
  InferenceServiceState get state => _state;

  /// Last error message if state is error
  String? get lastError => _lastError;

  /// Whether the service is ready for inference
  bool get isReady => _state == InferenceServiceState.ready;

  /// Initialize the inference service
  ///
  /// [modelPath] - Path to the Gemma 4 E2B model files
  /// [onProgress] - Callback for model download progress (0.0 to 1.0)
  Future<bool> initialize({
    required String modelPath,
    void Function(double progress)? onProgress,
  }) async {
    _state = InferenceServiceState.loading;
    _lastError = null;

    final success = await _client.initialize(
      modelPath: modelPath,
      onProgress: onProgress,
      onStateChange: (downloadState) {
        switch (downloadState) {
          case ModelDownloadState.ready:
            _state = InferenceServiceState.ready;
            break;
          case ModelDownloadState.error:
            _state = InferenceServiceState.error;
            _lastError = 'Failed to load model';
            break;
          default:
            break;
        }
      },
    );

    if (!success) {
      _state = InferenceServiceState.error;
      _lastError ??= 'Unknown initialization error';
    }

    return success;
  }

  /// Analyze documents for Track A (SNAP Benefits)
  ///
  /// [noticeImage] - The government notice image (JPEG bytes)
  /// [documents] - List of supporting document images (JPEG bytes)
  /// [documentDescriptions] - Optional descriptions for each document
  ///
  /// Returns an [InferenceResult] containing [TrackAResult]
  Future<InferenceResult<TrackAResult>> analyzeTrackA({
    required Uint8List noticeImage,
    required List<Uint8List> documents,
    List<String>? documentDescriptions,
  }) async {
    if (!isReady) {
      return InferenceResult.failure(
        errorMessage: 'Inference service not initialized',
        elapsed: Duration.zero,
      );
    }

    final stopwatch = Stopwatch()..start();

    // Build document labels
    final labels = PromptTemplates.generateDocumentLabels(
      documents.length,
      descriptions: documentDescriptions,
    );

    // Build the prompt
    final prompt = PromptTemplates.trackA(documentLabels: labels);

    // Combine images: notice first, then documents
    final allImages = [noticeImage, ...documents];

    // Run inference
    final response = await _client.chatWithImages(
      prompt: prompt,
      images: allImages,
    );

    stopwatch.stop();

    if (!response.isSuccess) {
      return InferenceResult.failure(
        errorMessage: response.errorMessage ?? 'Inference failed',
        elapsed: stopwatch.elapsed,
      );
    }

    // Parse the response
    final parseResult = ResponseParser.parseTrackA(response.rawText);

    if (!parseResult.isSuccess || parseResult.data == null) {
      return InferenceResult.failure(
        errorMessage: parseResult.errorMessage ?? 'Failed to parse response',
        elapsed: stopwatch.elapsed,
        rawResponse: response.rawText,
        confidence: ResponseParser.extractConfidenceFallback(response.rawText),
      );
    }

    // Calculate overall confidence
    final overallConfidence = _calculateTrackAConfidence(parseResult.data!);

    return InferenceResult.success(
      data: parseResult.data!,
      elapsed: stopwatch.elapsed,
      rawResponse: response.rawText,
      confidence: overallConfidence,
    );
  }

  /// Analyze documents for Track B (School Enrollment)
  ///
  /// [documents] - List of document images (JPEG bytes)
  /// [documentDescriptions] - Optional descriptions for each document
  ///
  /// Returns an [InferenceResult] containing [TrackBResult]
  Future<InferenceResult<TrackBResult>> analyzeTrackB({
    required List<Uint8List> documents,
    List<String>? documentDescriptions,
  }) async {
    if (!isReady) {
      return InferenceResult.failure(
        errorMessage: 'Inference service not initialized',
        elapsed: Duration.zero,
      );
    }

    final stopwatch = Stopwatch()..start();

    // Build document labels
    final labels = PromptTemplates.generateDocumentLabels(
      documents.length,
      descriptions: documentDescriptions,
    );

    // Build the prompt
    final prompt = PromptTemplates.trackB(documentLabels: labels);

    // Run inference
    final response = await _client.chatWithImages(
      prompt: prompt,
      images: documents,
    );

    stopwatch.stop();

    if (!response.isSuccess) {
      return InferenceResult.failure(
        errorMessage: response.errorMessage ?? 'Inference failed',
        elapsed: stopwatch.elapsed,
      );
    }

    // Parse the response
    final parseResult = ResponseParser.parseTrackB(response.rawText);

    if (!parseResult.isSuccess || parseResult.data == null) {
      return InferenceResult.failure(
        errorMessage: parseResult.errorMessage ?? 'Failed to parse response',
        elapsed: stopwatch.elapsed,
        rawResponse: response.rawText,
        confidence: ResponseParser.extractConfidenceFallback(response.rawText),
      );
    }

    // Use the overall confidence from the result
    final overallConfidence = parseResult.data!.overallConfidence;

    return InferenceResult.success(
      data: parseResult.data!,
      elapsed: stopwatch.elapsed,
      rawResponse: response.rawText,
      confidence: overallConfidence,
    );
  }

  /// Calculate overall confidence for Track A result
  ConfidenceLevel _calculateTrackAConfidence(TrackAResult result) {
    if (result.proofPack.isEmpty) return ConfidenceLevel.uncertain;

    final hasLow = result.proofPack.any((item) => item.confidence == ConfidenceLevel.low);
    final hasUncertain = result.proofPack.any((item) => item.confidence == ConfidenceLevel.uncertain);
    final allHigh = result.proofPack.every((item) => item.confidence == ConfidenceLevel.high);

    if (allHigh) return ConfidenceLevel.high;
    if (hasLow || hasUncertain) return ConfidenceLevel.low;
    return ConfidenceLevel.medium;
  }

  /// Dispose of resources
  void dispose() {
    _client.dispose();
    _state = InferenceServiceState.uninitialized;
  }
}

/// Extension methods for InferenceResult
extension InferenceResultExtension<T> on InferenceResult<T> {
  /// Whether this result requires human review
  bool get requiresReview =>
      confidence == ConfidenceLevel.low ||
      confidence == ConfidenceLevel.uncertain;

  /// Get a user-friendly status message
  String get statusMessage {
    if (!isSuccess) {
      return errorMessage ?? 'Analysis failed';
    }

    switch (confidence) {
      case ConfidenceLevel.high:
        return 'Analysis complete';
      case ConfidenceLevel.medium:
        return 'Analysis complete - please review';
      case ConfidenceLevel.low:
      case ConfidenceLevel.uncertain:
        return 'Analysis uncertain - please verify';
    }
  }
}

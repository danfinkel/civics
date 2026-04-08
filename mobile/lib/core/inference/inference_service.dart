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
import 'llama_client.dart';
import 'ocr_service.dart';
import 'prompt_templates.dart';
import 'response_parser.dart';
import 'model_manager.dart';
import 'cloud_fallback_client.dart';
import 'performance_metrics.dart';
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

/// Inference mode
enum InferenceMode {
  /// Use on-device model (preferred for privacy)
  onDevice,

  /// Use cloud fallback (faster, requires network)
  cloud,

  /// Automatically choose based on availability
  auto,
}

/// High-level service for document analysis inference
///
/// Pipeline: Image → OCR → llama.cpp → JSON Results
/// All processing happens on-device for privacy.
///
/// OCR uses Google ML Kit (on-device).
/// LLM uses llama.cpp with Gemma 4 E2B (on-device).
class InferenceService {
  // OCR for extracting text from images
  final OcrService _ocrService = OcrService();
  // LLM for analyzing extracted text
  final LlamaClient _localClient = LlamaClient();
  // Model download manager
  final ModelManager _modelManager = ModelManager();

  InferenceServiceState _state = InferenceServiceState.uninitialized;
  String? _lastError;
  InferenceMode _mode = InferenceMode.auto;

  /// Current service state
  InferenceServiceState get state => _state;

  /// Last error message if state is error
  String? get lastError => _lastError;

  /// Whether the service is ready for inference
  bool get isReady => _state == InferenceServiceState.ready;

  /// Current inference mode
  InferenceMode get mode => _mode;

  /// Set inference mode
  set mode(InferenceMode value) => _mode = value;

  /// Get the model manager for download UI
  ModelManager get modelManager => _modelManager;

  /// Check if cloud fallback is available
  Future<bool> get isCloudAvailable => CloudFallbackClient.isAvailable();

  /// Initialize the inference service
  ///
  /// Downloads model if needed, then initializes the appropriate client.
  /// [onProgress] - Callback for model download progress (0.0 to 1.0)
  /// [preferCloud] - If true, skip model download and use cloud
  Future<bool> initialize({
    void Function(double progress)? onProgress,
    bool preferCloud = false,
  }) async {
    _state = InferenceServiceState.loading;
    _lastError = null;

    final initStopwatch = Stopwatch()..start();

    // If cloud preferred or auto mode, try cloud first
    if (preferCloud || _mode == InferenceMode.cloud) {
      final cloudReady = await _cloudClient.initialize();
      if (cloudReady) {
        _state = InferenceServiceState.ready;
        _mode = InferenceMode.cloud;
        initStopwatch.stop();
        PerformanceMetrics.logInitialization(
          elapsed: initStopwatch.elapsed,
          success: true,
        );
        return true;
      }
    }

    // Try on-device if not cloud-only
    if (_mode != InferenceMode.cloud) {
      // Check if model is available
      final isModelReady = await _modelManager.isModelAvailable();

      if (!isModelReady) {
        // Download model
        final downloadResult = await _modelManager.downloadModel(
          onProgress: onProgress,
        );

        if (!downloadResult.success) {
          _state = InferenceServiceState.error;
          _lastError = downloadResult.errorMessage ?? 'Model download failed';
          initStopwatch.stop();
          PerformanceMetrics.logInitialization(
            elapsed: initStopwatch.elapsed,
            success: false,
            errorMessage: _lastError,
          );

          // Try cloud as fallback
          final cloudReady = await _cloudClient.initialize();
          if (cloudReady) {
            _state = InferenceServiceState.ready;
            _mode = InferenceMode.cloud;
            return true;
          }

          return false;
        }

        PerformanceMetrics.logDownload(
          elapsed: downloadResult.elapsed,
          success: true,
          bytesDownloaded: ModelManager.modelSizeBytes,
        );
      }

      // Initialize local client (llama.cpp)
      // Note: Model must be in GGUF format (converted from E2B)
      final modelPath = await _modelManager.modelPath;
      final localReady = await _localClient.initialize(
        modelPath: modelPath.replaceAll('.bin', '.gguf'),
        onProgress: onProgress,
      );

      if (localReady) {
        _state = InferenceServiceState.ready;
        _mode = InferenceMode.onDevice;
        initStopwatch.stop();
        PerformanceMetrics.logInitialization(
          elapsed: initStopwatch.elapsed,
          success: true,
        );
        return true;
      }
    }

    // All initialization failed
    _state = InferenceServiceState.error;
    _lastError = 'Failed to initialize any inference backend';
    initStopwatch.stop();
    PerformanceMetrics.logInitialization(
      elapsed: initStopwatch.elapsed,
      success: false,
      errorMessage: _lastError,
    );
    return false;
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

    // Run inference (local or cloud)
    final GemmaResponse response;
    if (_mode == InferenceMode.cloud) {
      response = await _cloudClient.chat(
        prompt: prompt,
        images: allImages,
        track: 'a',
      );
    } else {
      response = await _localClient.chatWithImages(
        prompt: prompt,
        images: allImages,
      );
    }

    stopwatch.stop();

    // Log metrics
    PerformanceMetrics.logInference(
      documentCount: allImages.length,
      elapsed: stopwatch.elapsed,
      success: response.isSuccess,
      errorMessage: response.errorMessage,
      metadata: {'mode': _mode.toString(), 'track': 'a'},
    );

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
    final response = await _localClient.chatWithImages(
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
    _localClient.dispose();
    _cloudClient.dispose();
    _modelManager.dispose();
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

/// OCR + LLM Pipeline Methods
///
/// These methods implement the privacy-first pipeline:
/// Image → OCR (ML Kit) → Text → llama.cpp → JSON
extension OcrLlmPipeline on InferenceService {
  /// Analyze documents using OCR + LLM pipeline
  ///
  /// 1. Extract text from all images using on-device OCR
  /// 2. Build prompt with extracted text
  /// 3. Run LLM inference on text only
  /// 4. Parse and return results
  ///
  /// All processing happens on-device. No cloud calls.
  Future<InferenceResult<TrackBResult>> analyzeTrackBWithOcr({
    required List<Uint8List> documents,
    List<String>? documentDescriptions,
  }) async {
    if (!isReady) {
      return InferenceResult.failure(
        errorMessage: 'Inference service not initialized',
        elapsed: Duration.zero,
      );
    }

    final totalStopwatch = Stopwatch()..start();

    // Step 1: OCR - Extract text from all images
    final ocrStopwatch = Stopwatch()..start();
    final ocrResults = await _ocrService.extractTextFromMultiple(documents);
    ocrStopwatch.stop();

    // Check if we got any text
    final hasAnyText = ocrResults.values.any((text) => text.isNotEmpty);
    if (!hasAnyText) {
      return InferenceResult.failure(
        errorMessage: 'Could not extract text from documents. Please ensure images are clear.',
        elapsed: totalStopwatch.elapsed,
      );
    }

    // Step 2: Build prompt with extracted text
    final extractedText = ocrResults.toPromptFormat();
    final prompt = _buildTextOnlyPrompt(
      track: 'b',
      extractedText: extractedText,
      documentCount: documents.length,
    );

    // Step 3: LLM inference on text
    final llmStopwatch = Stopwatch()..start();
    final response = await _localClient.chat(
      prompt: prompt,
      maxTokens: 2048,
    );
    llmStopwatch.stop();
    totalStopwatch.stop();

    // Log metrics
    PerformanceMetrics.logInference(
      documentCount: documents.length,
      elapsed: totalStopwatch.elapsed,
      success: response.isSuccess,
      errorMessage: response.errorMessage,
      metadata: {
        'mode': 'onDevice',
        'track': 'b',
        'ocr_time_ms': ocrStopwatch.elapsed.inMilliseconds,
        'llm_time_ms': llmStopwatch.elapsed.inMilliseconds,
      },
    );

    if (!response.isSuccess) {
      return InferenceResult.failure(
        errorMessage: response.errorMessage ?? 'Inference failed',
        elapsed: totalStopwatch.elapsed,
      );
    }

    // Step 4: Parse response
    final parseResult = ResponseParser.parseTrackB(response.rawText);

    if (!parseResult.isSuccess || parseResult.data == null) {
      return InferenceResult.failure(
        errorMessage: parseResult.errorMessage ?? 'Failed to parse response',
        elapsed: totalStopwatch.elapsed,
        rawResponse: response.rawText,
        confidence: ResponseParser.extractConfidenceFallback(response.rawText),
      );
    }

    return InferenceResult.success(
      data: parseResult.data!,
      elapsed: totalStopwatch.elapsed,
      rawResponse: response.rawText,
      confidence: parseResult.data!.overallConfidence,
    );
  }

  /// Build text-only prompt for OCR pipeline
  String _buildTextOnlyPrompt({
    required String track,
    required String extractedText,
    required int documentCount,
  }) {
    if (track == 'b') {
      return '''You are helping a family prepare their Boston Public Schools registration packet.

The BPS registration checklist requires:
- Proof of child's age (birth certificate or passport)
- TWO proofs of Boston residency from DIFFERENT categories.
  Valid categories: lease/deed, utility bill, bank statement, government mail, employer letter, notarized affidavit.
  Two documents from the same category count as only ONE proof.
  If both documents are leases, set duplicate_category_flag to true.
- Current immunization record
- Grade-level indicator (most recent report card or transcript, if applicable)

I have extracted text from $documentCount documents using OCR:

$extractedText

Based on this extracted text, analyze what documents are present and whether they satisfy the BPS requirements.

Return JSON:
{
  "requirements": [
    {
      "requirement": "",
      "status": "satisfied|questionable|missing",
      "matched_document": "[document name or MISSING]",
      "evidence": "[quote or observation]",
      "notes": ""
    }
  ],
  "duplicate_category_flag": true|false,
  "duplicate_category_explanation": "",
  "family_summary": "[plain language: what to bring, what to replace]"
}

If a document is a phone bill or cell phone statement, set its residency status to "questionable" — acceptance varies by BPS policy.
Important: never state that the packet guarantees registration or school assignment.''';
    }

    // Track A prompt
    return '''You are helping a Massachusetts resident prepare documents for a SNAP recertification or verification request.

I have extracted text from $documentCount documents using OCR:

$extractedText

Based on this extracted text, analyze what documents are present and what proof categories they might satisfy.

Return JSON with notice_summary, proof_pack, and action_summary.

Important: never state or imply that a document is accepted by the agency. Use 'appears to satisfy' and 'likely matches' only.''';
  }
}

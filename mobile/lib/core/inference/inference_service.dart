/// High-level inference service for CivicLens
///
/// Pipeline: Image → OCR → llama.cpp → JSON Results

import 'dart:typed_data';
import 'llama_client.dart';
import 'ocr_service.dart';
import 'response_parser.dart';
import 'model_manager.dart';
import '../models/track_a_result.dart';
import '../models/track_b_result.dart';

/// Result of an inference operation
class InferenceResult<T> {
  final T? data;
  final bool isSuccess;
  final String? errorMessage;
  final Duration elapsed;
  final String? rawResponse;
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
  uninitialized,
  loading,
  ready,
  error,
}

/// Inference mode
enum InferenceMode {
  onDevice,
  cloud,
  auto,
}

/// High-level service for document analysis inference
class InferenceService {
  static InferenceMode _mode = InferenceMode.onDevice;
  final OcrService _ocrService = OcrService();
  final LlamaClient _localClient = LlamaClient();
  final ModelManager _modelManager = ModelManager();

  InferenceServiceState _state = InferenceServiceState.uninitialized;
  String? _lastError;

  InferenceServiceState get state => _state;
  String? get lastError => _lastError;
  bool get isReady => _state == InferenceServiceState.ready;
  ModelManager get modelManager => _modelManager;
  InferenceMode get mode => _mode;
  set mode(InferenceMode value) => _mode = value;

  /// Initialize the inference service
  Future<bool> initialize({
    void Function(double progress)? onProgress,
    bool preferCloud = false,
  }) async {
    _state = InferenceServiceState.loading;
    _lastError = null;

    final initStopwatch = Stopwatch()..start();

    // Check if model is available
    final isModelReady = await _modelManager.isModelAvailable();

    if (!isModelReady) {
      _state = InferenceServiceState.error;
      _lastError = 'Model not available at ${await _modelManager.modelPath}';
      initStopwatch.stop();
      return false;
    }

    // Initialize local client (llama.cpp)
    final modelPath = await _modelManager.modelPath;
    final localReady = await _localClient.initialize(
      modelPath: modelPath,
      onProgress: onProgress,
    );

    if (localReady) {
      _state = InferenceServiceState.ready;
      initStopwatch.stop();
      return true;
    }

    _state = InferenceServiceState.error;
    _lastError = 'Failed to initialize llama.cpp';
    initStopwatch.stop();
    return false;
  }

  /// Analyze documents for Track B (legacy API - uses OCR pipeline)
  Future<InferenceResult<TrackBResult>> analyzeTrackB({
    required List<Uint8List> documents,
    List<String>? documentDescriptions,
  }) async {
    return analyzeTrackBWithOcr(documents: documents, documentDescriptions: documentDescriptions);
  }

  /// Analyze documents for Track B using OCR + LLM pipeline
  Future<InferenceResult<TrackBResult>> analyzeTrackBWithOcr({
    required List<Uint8List> documents,
    List<String>? documentDescriptions,
    void Function(int docIndex, int totalDocs)? onOcrProgress,
    void Function(double progress, {String? phase})? onLlmProgress,
  }) async {
    if (!isReady) {
      return InferenceResult.failure(
        errorMessage: 'Inference service not initialized',
        elapsed: Duration.zero,
      );
    }

    final totalStopwatch = Stopwatch()..start();

    // Step 1: OCR with progress
    final ocrStopwatch = Stopwatch()..start();
    final ocrResults = <int, String>{};

    for (var i = 0; i < documents.length; i++) {
      onOcrProgress?.call(i, documents.length);
      final result = await _ocrService.extractText(documents[i]);
      ocrResults[i] = result.text;
    }
    onOcrProgress?.call(documents.length, documents.length); // Complete

    ocrStopwatch.stop();

    final hasAnyText = ocrResults.values.any((text) => text.isNotEmpty);
    if (!hasAnyText) {
      return InferenceResult.failure(
        errorMessage: 'Could not extract text from documents',
        elapsed: totalStopwatch.elapsed,
      );
    }

    // Step 2: Build prompt
    final extractedText = _formatOcrResults(ocrResults, documentDescriptions);
    final prompt = _buildTextOnlyPrompt(
      track: 'b',
      extractedText: extractedText,
      documentCount: documents.length,
    );

    // Step 3: LLM inference with progress
    onLlmProgress?.call(0.0, phase: 'Starting…');
    final llmStopwatch = Stopwatch()..start();
    final response = await _localClient.chat(
      prompt: prompt,
      maxTokens: 2048,
      onProgress: onLlmProgress,
    );
    llmStopwatch.stop();
    onLlmProgress?.call(1.0, phase: 'Done');

    totalStopwatch.stop();

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
      );
    }

    return InferenceResult.success(
      data: parseResult.data!,
      elapsed: totalStopwatch.elapsed,
      rawResponse: response.rawText,
    );
  }

  String _formatOcrResults(Map<int, String> results, List<String>? descriptions) {
    final buffer = StringBuffer();
    for (var i = 0; i < results.length; i++) {
      final desc = descriptions != null && i < descriptions.length ? descriptions[i] : 'Document ${i + 1}';
      buffer.writeln('--- $desc ---');
      buffer.writeln(results[i] ?? '');
      buffer.writeln();
    }
    return buffer.toString();
  }

  String _buildTextOnlyPrompt({
    required String track,
    required String extractedText,
    required int documentCount,
  }) {
    if (track == 'b') {
      return '<start_of_turn>user\n'
          'You are helping a family prepare their Boston Public Schools registration packet.\n'
          '\n'
          'The BPS registration checklist requires:\n'
          '- Proof of child\'s age (birth certificate or passport)\n'
          '- TWO proofs of Boston residency from DIFFERENT categories\n'
          '- Current immunization record\n'
          '\n'
          'I have extracted text from $documentCount documents using OCR:\n'
          '\n'
          '$extractedText\n'
          '\n'
          'Analyze what documents are present and whether they satisfy BPS requirements.\n'
          '\n'
          'Respond with a JSON object containing:\n'
          '- "requirements": array of objects each with "requirement", "status" (satisfied/questionable/missing), "matched_document", and "evidence"\n'
          '- "duplicate_category_flag": boolean\n'
          '- "family_summary": string summarizing readiness\n'
          '<end_of_turn>\n'
          '<start_of_turn>model\n';
    }
    return '';
  }

  void dispose() {
    _localClient.dispose();
    _ocrService.dispose();
    _modelManager.dispose();
    _state = InferenceServiceState.uninitialized;
  }
}


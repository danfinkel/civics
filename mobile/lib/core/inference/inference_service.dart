/// High-level inference service for CivicLens
///
/// Pipeline: Image → OCR → llama.cpp → JSON Results
///
/// llama_cpp_dart requires the full prompt in one batch (`nBatch`); keep prompts
/// under ~1900 tokens (chars cap + clamp) so we avoid LlamaException and jetsam.

import 'package:flutter/foundation.dart';

import 'llama_client.dart';
import 'model_manager.dart';
import 'ocr_service.dart';
import 'prompt_templates.dart';
import 'response_parser.dart';
import '../models/track_a_result.dart';
import '../models/track_b_result.dart';
import '../utils/eval_mode.dart';

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

/// Track A can need ~4k chars of OCR (notice + two pay stubs) plus preamble; keep
/// under `nCtx` with room for output (see llama_client nBatch/nCtx).
const int _kMaxLocalLlmPromptChars = 5600;

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
    var prompt = _buildTextOnlyPrompt(
      track: 'b',
      extractedText: extractedText,
      documentCount: documents.length,
    );
    prompt = _clampPromptForLocalLlm(prompt);

    // Step 3: LLM inference with progress
    onLlmProgress?.call(0.0, phase: 'Starting…');
    final llmStopwatch = Stopwatch()..start();
    final response = await _localClient.chat(
      prompt: prompt,
      maxTokens: 1400,
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

  /// Track A: the notice often puts **response deadline / consequences** in the
  /// body below the letterhead. Supporting docs were at 600 chars, which cut
  /// typical pay stubs (~1k OCR) and injected `[... text truncated...]` — the model
  /// then told users the "document" was truncated. Use ~1100 per supporting doc.
  String _formatOcrResultsTrackA(
    Map<int, String> results,
    List<String> descriptions,
  ) {
    const noticeMax = 2000;
    const supportingMax = 1100;
    const maxTotalChars = 4200;
    final buffer = StringBuffer();
    var total = 0;
    final n = results.length;
    for (var i = 0; i < n; i++) {
      final desc =
          i < descriptions.length ? descriptions[i] : 'Document ${i + 1}';
      final cap = i == 0 ? noticeMax : supportingMax;
      var body = results[i] ?? '';
      if (body.length > cap) {
        body =
            '${body.substring(0, cap)}\n[... text truncated for model limits ...]';
      }
      final header = '--- $desc ---\n';
      final section = '$header$body\n\n';
      if (total + section.length > maxTotalChars) {
        final remaining = maxTotalChars - total - header.length;
        if (remaining > 200) {
          buffer.write(header);
          buffer.writeln(body.substring(0, remaining.clamp(0, body.length)));
          buffer.writeln('[... document truncated; later pages omitted ...]');
        }
        break;
      }
      buffer.write(section);
      total += section.length;
    }
    return buffer.toString();
  }

  /// Per-section and total caps (tight: paired with [_clampPromptForLocalLlm]).
  String _formatOcrResults(
    Map<int, String> results,
    List<String>? descriptions, {
    int maxCharsPerSection = 800,
    int maxTotalChars = 2400,
  }) {
    final buffer = StringBuffer();
    var total = 0;
    for (var i = 0; i < results.length; i++) {
      final desc = descriptions != null && i < descriptions.length
          ? descriptions[i]
          : 'Document ${i + 1}';
      var body = results[i] ?? '';
      if (body.length > maxCharsPerSection) {
        body =
            '${body.substring(0, maxCharsPerSection)}\n[... text truncated for model limits ...]';
      }
      final header = '--- $desc ---\n';
      final section = '$header$body\n\n';
      if (total + section.length > maxTotalChars) {
        final remaining = maxTotalChars - total - header.length;
        if (remaining > 200) {
          buffer.write(header);
          buffer.writeln(body.substring(0, remaining.clamp(0, body.length)));
          buffer.writeln('[... document truncated; later pages omitted ...]');
        }
        break;
      }
      buffer.write(section);
      total += section.length;
    }
    return buffer.toString();
  }

  /// Hard cap final prompt length; preserves Gemma turn markers and instruction head.
  String _clampPromptForLocalLlm(String prompt) {
    if (prompt.length <= _kMaxLocalLlmPromptChars) return prompt;

    const endTurn = '<end_of_turn>';
    final endIdx = prompt.lastIndexOf(endTurn);
    if (endIdx < 0) {
      return '${prompt.substring(0, _kMaxLocalLlmPromptChars - 40)}\n\n[Truncated]';
    }

    final tail = prompt.substring(endIdx);
    final headBudget = _kMaxLocalLlmPromptChars - tail.length - 60;
    if (headBudget < 200) {
      return '${prompt.substring(0, _kMaxLocalLlmPromptChars - 40)}\n\n[Truncated]';
    }

    var head = prompt.substring(0, endIdx);
    if (head.length > headBudget) {
      head =
          '${head.substring(0, headBudget)}\n\n[Body truncated for on-device limits.]';
    }
    return '$head$tail';
  }

  String _buildTextOnlyPrompt({
    required String track,
    required String extractedText,
    required int documentCount,
  }) {
    if (track == 'b') {
      return '<start_of_turn>user\n'
          'BPS registration packet check. Requirements: child age proof (birth cert/passport); '
          'TWO Boston residency proofs from different categories (lease/deed, utility, bank stmt, '
          'gov mail, employer letter, affidavit); immunization record. Two docs same category = '
          'only one proof — set duplicate_category_flag true.\n\n'
          'OCR from $documentCount document(s) (may have errors):\n\n'
          '$extractedText\n\n'
          'Return ONLY valid JSON (no markdown). '
          '{"requirements":[{"requirement":"","status":"satisfied|questionable|missing",'
          '"matched_document":"","evidence":"","notes":"","confidence":"high|medium|low"}],'
          '"duplicate_category_flag":false,"duplicate_category_explanation":"",'
          '"family_summary":""}\n'
          '<end_of_turn>\n'
          '<start_of_turn>model\n';
    }
    return '';
  }

  /// Track A: notice + supporting photos → OCR → LLM → [TrackAResult].
  Future<InferenceResult<TrackAResult>> analyzeTrackAWithOcr({
    required List<Uint8List> documents,
    required List<String> supportingDocumentLabels,
    void Function(int docIndex, int totalDocs)? onOcrProgress,
    void Function(double progress, {String? phase})? onLlmProgress,
  }) async {
    if (!isReady) {
      return InferenceResult.failure(
        errorMessage: 'Inference service not initialized',
        elapsed: Duration.zero,
      );
    }

    if (documents.isEmpty) {
      return InferenceResult.failure(
        errorMessage: 'No documents to analyze',
        elapsed: Duration.zero,
      );
    }

    final totalStopwatch = Stopwatch()..start();

    final ocrStopwatch = Stopwatch()..start();
    final ocrResults = <int, String>{};

    for (var i = 0; i < documents.length; i++) {
      onOcrProgress?.call(i, documents.length);
      final result = await _ocrService.extractText(documents[i]);
      ocrResults[i] = result.text;
    }
    onOcrProgress?.call(documents.length, documents.length);
    ocrStopwatch.stop();

    if (kInferenceDiagnostics) {
      for (var i = 0; i < documents.length; i++) {
        final t = ocrResults[i] ?? '';
        _inferenceDiag(
          '[TrackA][ocr] doc=$i len=${t.length} trim=${t.trim().length} '
          'preview=${_inferenceOneLinePreview(t)}',
        );
      }
    }

    final hasAnyText = ocrResults.values.any((text) => text.trim().isNotEmpty);
    if (!hasAnyText) {
      return InferenceResult.failure(
        errorMessage: 'Could not extract text from documents',
        elapsed: totalStopwatch.elapsed,
      );
    }

    final descriptions = <String>[
      'Government notice',
      ...supportingDocumentLabels,
    ];
    final extractedText = _formatOcrResultsTrackA(ocrResults, descriptions);

    final preamble =
        PromptTemplates.trackAOcrOnly(documentLabels: supportingDocumentLabels);
    final userBlock = '$preamble\n\n'
        'IMPORTANT: No images are attached. Base your analysis only on this '
        'OCR output (errors and gaps are possible).\n'
        'If a section ends with the line '
        '"[... text truncated for model limits ...]", only part of the extracted '
        'text was included in this prompt — that is not a problem with the '
        'resident photo. Do not say their upload or document image is '
        '"truncated"; use caveats only for real gaps in the OCR text.\n\n'
        '$extractedText';

    var prompt = userBlock.contains('<start_of_turn>')
        ? userBlock
        : '<start_of_turn>user\n$userBlock\n<end_of_turn>\n<start_of_turn>model\n';
    final promptBeforeClamp = prompt;
    prompt = _clampPromptForLocalLlm(prompt);
    if (kInferenceDiagnostics) {
      _inferenceDiag(
        '[TrackA][prompt] formattedOcrLen=${extractedText.length} '
        'beforeClamp=${promptBeforeClamp.length} afterClamp=${prompt.length} '
        'clamped=${prompt.length < promptBeforeClamp.length}',
      );
    }

    onLlmProgress?.call(0.0, phase: 'Starting…');
    final llmStopwatch = Stopwatch()..start();
    final response = await _localClient.chat(
      prompt: prompt,
      maxTokens: 1400,
      onProgress: onLlmProgress,
    );
    llmStopwatch.stop();
    onLlmProgress?.call(1.0, phase: 'Done');
    totalStopwatch.stop();

    if (!response.isSuccess) {
      if (kInferenceDiagnostics) {
        _inferenceDiag(
          '[TrackA][llm] success=false err=${response.errorMessage}',
        );
      }
      return InferenceResult.failure(
        errorMessage: response.errorMessage ?? 'Inference failed',
        elapsed: totalStopwatch.elapsed,
      );
    }

    if (kInferenceDiagnostics) {
      final raw = response.rawText;
      _inferenceDiag(
        '[TrackA][llm] success=true ms=${llmStopwatch.elapsedMilliseconds} '
        'rawLen=${raw.length}',
      );
      _inferenceDiag('[TrackA][llm.raw] ${_inferenceOneLinePreview(raw, max: 2000)}');
    }

    final parseResult = ResponseParser.parseTrackA(response.rawText);
    if (kInferenceDiagnostics) {
      if (parseResult.isSuccess && parseResult.data != null) {
        final d = parseResult.data!;
        _inferenceDiag(
          '[TrackA][parse] ok=true deadline=${d.noticeSummary.deadline} '
          'uncertain=${d.noticeSummary.isUncertain} '
          'categories=${d.noticeSummary.requestedCategories} '
          'proofItems=${d.proofPack.length} actionLen=${d.actionSummary.length}',
        );
      } else {
        _inferenceDiag(
          '[TrackA][parse] ok=false err=${parseResult.errorMessage}',
        );
      }
    }
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

  /// Raw LLM output for eval harness (`/infer`). Runs OCR on [imageBytes] when
  /// non-empty, appends text to the user message, then calls the local llama isolate.
  ///
  /// [temperature] is passed through (sampler wiring in the isolate may still
  /// be greedy). Callers may pass `track` via the prompt until routing exists.
  Future<String?> inferRaw({
    required Uint8List imageBytes,
    required String prompt,
    double temperature = 0.0,
    int? tokenBudget,
  }) async {
    if (!isReady) {
      throw StateError('Inference service not initialized');
    }

    final maxTokens = tokenBudget ?? 2048;
    var userContent = prompt.trim();

    if (imageBytes.isNotEmpty) {
      final ocr = await _ocrService.extractText(imageBytes);
      if (ocr.text.trim().isNotEmpty) {
        userContent =
            '$userContent\n\n--- Extracted document text (OCR) ---\n${ocr.text}';
      }
    }

    var fullPrompt = userContent.contains('<start_of_turn>')
        ? userContent
        : '<start_of_turn>user\n$userContent\n<end_of_turn>\n<start_of_turn>model\n';
    fullPrompt = _clampPromptForLocalLlm(fullPrompt);

    final response = await _localClient.chat(
      prompt: fullPrompt,
      temperature: temperature,
      maxTokens: maxTokens,
    );

    if (!response.isSuccess) {
      throw StateError(response.errorMessage ?? 'Inference failed');
    }
    return response.rawText;
  }

  void dispose() {
    _localClient.dispose();
    _ocrService.dispose();
    _modelManager.dispose();
    _state = InferenceServiceState.uninitialized;
  }
}

void _inferenceDiag(String line) {
  if (kInferenceDiagnostics) {
    debugPrint(line);
  }
}

String _inferenceOneLinePreview(String s, {int max = 500}) {
  final t = s.replaceAll('\r', ' ').replaceAll('\n', '\\n');
  if (t.length <= max) return t;
  return '${t.substring(0, max)}…(+${t.length - max} more chars)';
}

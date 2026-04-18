import 'dart:typed_data';
import '../../core/imaging/document_capture.dart';
import '../../core/inference/inference.dart';

/// View state for Track B screen
enum TrackBViewState {
  idle,
  loading,
  success,
  error,
}

/// Progress info for loading state ([percent] is always **0.0–1.0** overall).
class AnalysisProgress {
  final String message;
  final double percent;

  const AnalysisProgress({
    required this.message,
    required this.percent,
  });
}

/// Document slot for Track B upload
class DocumentSlot {
  final String title;
  final bool required;
  final String description;
  CapturedDocument? document;

  DocumentSlot({
    required this.title,
    required this.required,
    required this.description,
    this.document,
  });

  bool get isFilled => document != null;
}

/// Controller for Track B (School Enrollment) flow
class TrackBController {
  final InferenceService _service = InferenceService();

  // View state
  TrackBViewState _state = TrackBViewState.idle;
  TrackBViewState get state => _state;

  // Error message if state is error
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // Result if state is success
  TrackBResult? _result;
  TrackBResult? get result => _result;

  /// Set when [analyzeDocuments] completes successfully (cleared on new run / [clearAll]).
  DateTime? _analysisCompletedAt;
  DateTime? get analysisCompletedAt => _analysisCompletedAt;

  // Inference mode used
  InferenceMode? _modeUsed;
  InferenceMode? get modeUsed => _modeUsed;

  // Progress for loading state
  AnalysisProgress _progress = const AnalysisProgress(
    message: 'Initializing...',
    percent: 0.0,
  );
  AnalysisProgress get progress => _progress;

  // Callback for progress updates
  void Function(AnalysisProgress)? onProgress;

  /// When false, Grade Indicator slot is hidden and excluded from analysis.
  bool includeGradeIndicator = false;

  void setIncludeGradeIndicator(bool value) {
    includeGradeIndicator = value;
    if (!value) {
      clearDocument(4);
    }
  }

  /// Slot indices shown in the upload UI (0–4; index 4 is grade).
  List<int> get visibleSlotIndices =>
      includeGradeIndicator ? [0, 1, 2, 3, 4] : [0, 1, 2, 3];

  // Document slots for BPS registration
  final List<DocumentSlot> slots = [
    DocumentSlot(
      title: 'Proof of Age',
      required: true,
      description: 'Birth certificate or passport',
    ),
    DocumentSlot(
      title: 'Residency Proof 1',
      required: true,
      description: 'Lease, deed, or utility bill',
    ),
    DocumentSlot(
      title: 'Residency Proof 2',
      required: true,
      description: 'From a different category than Proof 1',
    ),
    DocumentSlot(
      title: 'Immunization Record',
      required: true,
      description: 'Current vaccination record',
    ),
    DocumentSlot(
      title: 'Grade Indicator',
      required: false,
      description: 'Report card or transcript (if applicable)',
    ),
  ];

  /// Whether all required slots are filled
  bool get canAnalyze {
    return slots.where((s) => s.required).every((s) => s.isFilled);
  }

  /// Count of filled slots
  int get filledCount => slots.where((s) => s.isFilled).length;

  /// Set document for a slot
  void setDocument(int index, CapturedDocument doc) {
    if (index >= 0 && index < slots.length) {
      slots[index].document = doc;
    }
  }

  /// Clear a slot
  void clearDocument(int index) {
    if (index >= 0 && index < slots.length) {
      slots[index].document = null;
    }
  }

  /// Clear all slots
  void clearAll() {
    for (final slot in slots) {
      slot.document = null;
    }
    includeGradeIndicator = false;
    _result = null;
    _errorMessage = null;
    _analysisCompletedAt = null;
    _state = TrackBViewState.idle;
  }

  /// Initialize the inference service
  Future<bool> initializeService() async {
    final success = await _service.initialize(preferCloud: true);
    _modeUsed = _service.mode;
    return success;
  }

  /// Update progress and notify listeners
  void _updateProgress(String message, double percent) {
    _progress = AnalysisProgress(message: message, percent: percent);
    onProgress?.call(_progress);
  }

  /// Analyze documents using InferenceService with progress tracking
  Future<void> analyzeDocuments() async {
    _state = TrackBViewState.loading;
    _errorMessage = null;
    _analysisCompletedAt = null;
    _updateProgress('Initializing...', 0.0);

    // Initialize service if not ready
    if (!_service.isReady) {
      final initialized = await initializeService();
      if (!initialized) {
        _state = TrackBViewState.error;
        _errorMessage = _service.lastError ?? 'Failed to initialize inference service';
        return;
      }
    }

    // Collect images and descriptions
    final images = <Uint8List>[];
    final descriptions = <String>[];

    for (var i = 0; i < slots.length; i++) {
      if (i == 4 && !includeGradeIndicator) continue;
      final slot = slots[i];
      if (slot.isFilled) {
        images.add(slot.document!.imageBytes);
        descriptions.add('${slot.title}: ${slot.description}');
      }
    }

    if (images.isEmpty) {
      _state = TrackBViewState.error;
      _errorMessage = 'Add at least one document to get started';
      return;
    }

    // Run inference with progress tracking
    // OCR phase: 0-30%, LLM phase: 30-100%
    final inferenceResult = await _service.analyzeTrackBWithOcr(
      documents: images,
      documentDescriptions: descriptions,
      onOcrProgress: (docIndex, totalDocs) {
        final total = totalDocs > 0 ? totalDocs : 1;
        // OCR phase uses first 30% of the overall bar (final callback uses docIndex == totalDocs).
        final p = ((docIndex / total) * 0.3).clamp(0.0, 0.3);
        final msg = docIndex >= totalDocs
            ? 'Finished reading documents…'
            : 'Reading document ${docIndex + 1} of $totalDocs...';
        _updateProgress(msg, p);
      },
      onLlmProgress: (progress, {phase}) {
        // progress from llama is 0.0–1.0 within the LLM step; map to 30–100% of overall.
        final llm = progress.clamp(0.0, 1.0);
        final p = (0.3 + llm * 0.7).clamp(0.0, 1.0);
        final message = (phase != null && phase.isNotEmpty)
            ? phase
            : (llm < 0.5 ? 'Analyzing documents...' : 'Almost done...');
        _updateProgress(message, p);
      },
    );

    if (inferenceResult.isSuccess && inferenceResult.data != null) {
      _result = inferenceResult.data;
      _analysisCompletedAt = DateTime.now();
      _state = TrackBViewState.success;
    } else {
      _state = TrackBViewState.error;
      _errorMessage = inferenceResult.errorMessage ?? 'Analysis failed';
    }
  }

  /// Retry analysis (e.g., after error)
  Future<void> retryAnalysis() async {
    await analyzeDocuments();
  }

  /// Switch to cloud mode and retry
  Future<void> switchToCloudAndRetry() async {
    _service.mode = InferenceMode.cloud;
    await analyzeDocuments();
  }

  void dispose() {
    _service.dispose();
  }
}

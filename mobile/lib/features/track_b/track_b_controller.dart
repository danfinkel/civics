import 'dart:typed_data';
import '../../core/imaging/document_capture.dart';
import '../../core/inference/inference.dart';
import '../../core/models/track_b_result.dart';

/// View state for Track B screen
enum TrackBViewState {
  idle,
  loading,
  success,
  error,
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

  // Inference mode used
  InferenceMode? _modeUsed;
  InferenceMode? get modeUsed => _modeUsed;

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
    _result = null;
    _errorMessage = null;
    _state = TrackBViewState.idle;
  }

  /// Initialize the inference service
  Future<bool> initializeService() async {
    final success = await _service.initialize(preferCloud: true);
    _modeUsed = _service.mode;
    return success;
  }

  /// Analyze documents using InferenceService
  Future<void> analyzeDocuments() async {
    _state = TrackBViewState.loading;
    _errorMessage = null;

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

    for (final slot in slots) {
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

    // Run inference
    final inferenceResult = await _service.analyzeTrackB(
      documents: images,
      documentDescriptions: descriptions,
    );

    if (inferenceResult.isSuccess && inferenceResult.data != null) {
      _result = inferenceResult.data;
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

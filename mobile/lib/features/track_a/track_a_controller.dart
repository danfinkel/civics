import 'dart:typed_data';
import '../../core/imaging/document_capture.dart';
import '../../core/inference/inference.dart';

/// Controller for Track A (SNAP Benefits) flow
class TrackAController {
  final InferenceService _service = InferenceService();

  // The government notice
  CapturedDocument? notice;

  // Supporting documents (up to 3)
  final List<CapturedDocument?> supportingDocuments = [null, null, null];

  /// Whether we have enough documents to analyze
  bool get canAnalyze =>
      notice != null &&
      supportingDocuments.any((d) => d != null);

  /// Set the government notice
  void setNotice(CapturedDocument doc) {
    notice = doc;
  }

  /// Clear the notice
  void clearNotice() {
    notice = null;
  }

  /// Set a supporting document
  void setSupportingDocument(int index, CapturedDocument doc) {
    if (index >= 0 && index < supportingDocuments.length) {
      supportingDocuments[index] = doc;
    }
  }

  /// Clear a supporting document
  void clearSupportingDocument(int index) {
    if (index >= 0 && index < supportingDocuments.length) {
      supportingDocuments[index] = null;
    }
  }

  /// Clear all documents
  void clearAll() {
    notice = null;
    for (int i = 0; i < supportingDocuments.length; i++) {
      supportingDocuments[i] = null;
    }
  }

  /// Load model + OCR stack (same path as Track B).
  Future<bool> initializeService() async {
    return _service.initialize(preferCloud: true);
  }

  /// Analyze documents using on-device OCR + llama.cpp (via [InferenceService]).
  Future<TrackAResult> analyzeDocuments() async {
    if (notice == null) {
      throw Exception('Government notice is required');
    }

    if (!_service.isReady) {
      final ok = await initializeService();
      if (!ok) {
        throw Exception(
          _service.lastError ?? 'Could not start document review on this device',
        );
      }
    }

    final images = <Uint8List>[notice!.imageBytes];
    final supportingLabels = <String>[];

    for (int i = 0; i < supportingDocuments.length; i++) {
      final doc = supportingDocuments[i];
      if (doc != null) {
        images.add(doc.imageBytes);
        supportingLabels.add('Document ${i + 1}');
      }
    }

    final result = await _service.analyzeTrackAWithOcr(
      documents: images,
      supportingDocumentLabels: supportingLabels,
    );

    if (!result.isSuccess || result.data == null) {
      throw Exception(result.errorMessage ?? 'Analysis failed');
    }

    return result.data!;
  }

  /// Background read of the notice for step-2 hints; returns null on any failure.
  Future<TrackANoticePreview?> prefetchNoticePreview() async {
    if (notice == null) return null;

    if (!_service.isReady) {
      final ok = await initializeService();
      if (!ok) return null;
    }

    final result = await _service.analyzeTrackANoticePreview(
      noticeBytes: notice!.imageBytes,
    );

    if (!result.isSuccess || result.data == null) return null;
    return result.data;
  }

  void dispose() {
    _service.dispose();
  }
}

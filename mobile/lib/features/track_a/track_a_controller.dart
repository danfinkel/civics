import 'dart:typed_data';
import '../../core/imaging/document_capture.dart';
import '../../core/inference/gemma_client.dart';
import '../../core/inference/prompt_templates.dart';
import '../../core/inference/response_parser.dart';
import '../../core/models/track_a_result.dart';

/// Controller for Track A (SNAP Benefits) flow
class TrackAController {
  final GemmaClient _gemmaClient = GemmaClient();

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

  /// Analyze documents using Gemma 4
  Future<TrackAResult> analyzeDocuments() async {
    if (notice == null) {
      throw Exception('Government notice is required');
    }

    // Build document labels for prompt
    final documentLabels = <String>[];
    final images = <Uint8List>[];

    // Notice is always first
    images.add(notice!.imageBytes);

    // Add supporting documents
    for (int i = 0; i < supportingDocuments.length; i++) {
      final doc = supportingDocuments[i];
      if (doc != null) {
        documentLabels.add('Document ${i + 1}');
        images.add(doc.imageBytes);
      }
    }

    // Generate prompt
    final prompt = PromptTemplates.trackA(documentLabels: documentLabels);

    // Run inference
    final response = await _gemmaClient.chat(
      prompt: prompt,
      images: images,
    );

    if (!response.success) {
      throw Exception(response.error ?? 'Inference failed');
    }

    // Parse response
    final result = ResponseParser.parseTrackA(response.rawText);
    if (result == null) {
      throw Exception('Could not parse response');
    }

    return result;
  }

  void dispose() {
    _gemmaClient.dispose();
  }
}

import 'dart:typed_data';
import '../../core/imaging/document_capture.dart';
import '../../core/inference/gemma_client.dart';
import '../../core/inference/prompt_templates.dart';
import '../../core/inference/response_parser.dart';
import '../../core/models/track_b_result.dart';

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
  final GemmaClient _gemmaClient = GemmaClient();

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
  }

  /// Analyze documents using Gemma 4
  Future<TrackBResult> analyzeDocuments() async {
    // Build document labels for prompt
    final documentLabels = <String>[];
    final images = <Uint8List>[];

    for (int i = 0; i < slots.length; i++) {
      final slot = slots[i];
      if (slot.isFilled) {
        documentLabels.add('${slot.title}: ${slot.description}');
        images.add(slot.document!.imageBytes);
      }
    }

    // Generate prompt
    final prompt = PromptTemplates.trackB(documentLabels: documentLabels);

    // Run inference
    final response = await _gemmaClient.chat(
      prompt: prompt,
      images: images,
    );

    if (!response.success) {
      throw Exception(response.error ?? 'Inference failed');
    }

    // Parse response
    final result = ResponseParser.parseTrackB(response.rawText);
    if (result == null) {
      throw Exception('Could not parse response');
    }

    return result;
  }

  void dispose() {
    _gemmaClient.dispose();
  }
}

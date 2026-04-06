/// Prompt templates for Track A (SNAP) and Track B (BPS) inference
///
/// These templates are based on the spike findings documented in:
/// - spike/docs/day3_findings.md (end-to-end scenarios)
/// - spike/docs/day5_decision_memo.md (final prompt design)
///
/// Key design decisions from spike:
/// - Use "likely satisfies" language, never "accepted"
/// - Include confidence levels for human review
/// - Always include caveats when confidence is not high
/// - Set UNCERTAIN for blurry/unreadable documents (don't guess)

/// Templates for generating prompts for document analysis
class PromptTemplates {
  /// Track A — SNAP Proof-Pack Builder
  static String trackA({required List<String> documentLabels}) {
    final documentList = documentLabels
        .asMap()
        .entries
        .map((e) => '${e.key + 1}. ${e.value}')
        .join('\n');

    return '''You are helping a Massachusetts resident prepare documents for a SNAP recertification or verification request.

The resident has shared:
1. A government notice (image attached)
2. The following documents they have at home (images attached):
$documentList

Your job:

Step 1: Read the notice and identify what proof categories are being requested and the response deadline.

Step 2: For each document, classify it and assess whether it likely satisfies one of the requested categories.

Step 3: Return a structured JSON result:

{
  "notice_summary": {
    "requested_categories": [],
    "deadline": "",
    "consequence": ""
  },
  "proof_pack": [
    {
      "category": "",
      "matched_document": "[document name or MISSING]",
      "assessment": "likely_satisfies|likely_does_not_satisfy|missing|uncertain",
      "confidence": "high|medium|low",
      "evidence": "[quote from document]",
      "caveats": ""
    }
  ],
  "action_summary": "[one paragraph in plain language for the resident]"
}

Important: never state or imply that a document is accepted by the agency. Use 'appears to satisfy' and 'likely matches' only.
Always show caveats when confidence is not high.
If the notice image is blurry or you cannot clearly read the text, set notice_summary fields to "UNCERTAIN" — do not guess.'';
  }

  /// Track B: BPS Enrollment Packet Checker
  ///
  /// Helps families prepare Boston Public Schools registration packets.
  ///
  /// [documentLabels] - List of document descriptions, e.g.:
  ///   ["Document 1: birth certificate", "Document 2: lease agreement"]
  ///
  /// Returns the complete prompt string for the model
  static String trackB({required List<String> documentLabels}) {
    final documentList = documentLabels
        .asMap()
        .entries
        .map((e) => '${e.key + 1}. ${e.value}')
        .join('\n');

    return '''You are helping a family prepare their Boston Public Schools registration packet.

The BPS registration checklist requires:
- Proof of child's age (birth certificate or passport)
- TWO proofs of Boston residency from DIFFERENT categories.
  Valid categories: lease/deed, utility bill, bank statement, government mail, employer letter, notarized affidavit.
  Two documents from the same category count as only ONE proof.
  If both documents are leases, set duplicate_category_flag to true.
- Current immunization record
- Grade-level indicator (most recent report card or transcript, if applicable)

The family has uploaded the following documents (images attached):
$documentList

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

  /// Generate document labels for the prompt
  ///
  /// [count] - Number of documents
  /// [descriptions] - Optional descriptions for each document
  ///
  /// Returns a list of formatted labels like:
  ///   ["Document 1", "Document 2: pay stub", ...]
  static List<String> generateDocumentLabels(
    int count, {
    List<String>? descriptions,
  }) {
    return List.generate(count, (index) {
      final docNum = index + 1;
      final description = descriptions != null && index < descriptions.length
          ? ': ${descriptions[index]}'
          : '';
      return 'Document $docNum$description';
    });
  }

  /// Track A with specific notice document
  ///
  /// Use this when you want to explicitly label the notice separately
  /// from supporting documents.
  ///
  /// [noticeDescription] - Description of the notice, e.g. "DTA verification notice"
  /// [documentLabels] - Labels for supporting documents
  static String trackAWithNotice({
    required String noticeDescription,
    required List<String> documentLabels,
  }) {
    final documentList = documentLabels
        .asMap()
        .entries
        .map((e) => '${e.key + 1}. ${e.value}')
        .join('\n');

    return '''You are helping a Massachusetts resident prepare documents for a SNAP recertification or verification request.

The resident has shared:
1. A government notice: $noticeDescription (first image attached)
2. The following documents they have at home (subsequent images attached):
$documentList

Your job:

Step 1: Read the notice and identify what proof categories are being requested and the response deadline.

Step 2: For each document, classify it and assess whether it likely satisfies one of the requested categories.

Step 3: Return a structured JSON result:

{
  "notice_summary": {
    "requested_categories": [],
    "deadline": "",
    "consequence": ""
  },
  "proof_pack": [
    {
      "category": "",
      "matched_document": "[document name or MISSING]",
      "assessment": "likely_satisfies|likely_does_not_satisfy|missing|uncertain",
      "confidence": "high|medium|low",
      "evidence": "[quote from document]",
      "caveats": ""
    }
  ],
  "action_summary": "[one paragraph in plain language for the resident]"
}

Important: never state or imply that a document is accepted by the agency. Use 'appears to satisfy' and 'likely matches' only.
Always show caveats when confidence is not high.
If the notice image is blurry or you cannot clearly read the text, set notice_summary fields to "UNCERTAIN" — do not guess.''';
  }
}

/// Extension methods for working with prompt templates
extension PromptTemplatesExtension on String {
  /// Check if this prompt is for Track A
  bool get isTrackA => contains('SNAP recertification');

  /// Check if this prompt is for Track B
  bool get isTrackB => contains('Boston Public Schools');

  /// Extract the document list from a prompt
  ///
  /// Returns the text between the document list header and the next section
  String? extractDocumentList() {
    final lines = split('\n');
    final startIndex = lines.indexWhere(
      (line) => line.contains('documents') || line.contains('uploaded'),
    );

    if (startIndex == -1) return null;

    // Find the end of the document list (next empty line or "Your job")
    final endIndex = lines.sublist(startIndex + 1).indexWhere(
          (line) =>
              line.trim().isEmpty ||
              line.contains('Your job') ||
              line.contains('Step 1'),
        );

    if (endIndex == -1) {
      return lines.sublist(startIndex + 1).join('\n');
    }

    return lines.sublist(startIndex + 1, startIndex + 1 + endIndex).join('\n');
  }
}

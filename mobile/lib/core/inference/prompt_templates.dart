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
  /// Track A: SNAP Proof-Pack Builder
  static String trackA({required List<String> documentLabels}) {
    final documentList = documentLabels
        .asMap()
        .entries
        .map((e) => '${e.key + 1}. ${e.value}')
        .join('\n');

    return "You are helping a Massachusetts resident prepare documents for a SNAP recertification or verification request.\n\n"
        "The resident has shared:\n"
        "1. A government notice (image attached)\n"
        "2. The following documents they have at home (images attached):\n"
        "$documentList\n\n"
        "Your job:\n\n"
        "Step 1: Read the notice and identify what proof categories are being requested and the response deadline.\n\n"
        "Step 2: For each document, classify it and assess whether it likely satisfies one of the requested categories.\n\n"
        "Step 3: Return a structured JSON result:\n\n"
        "{\n"
        '  "notice_summary": {\n'
        '    "requested_categories": [],\n'
        '    "deadline": "",\n'
        '    "consequence": ""\n'
        "  },\n"
        '  "proof_pack": [\n'
        "    {\n"
        '      "category": "",\n'
        '      "matched_document": "[document name or MISSING]",\n'
        '      "assessment": "likely_satisfies|likely_does_not_satisfy|missing|uncertain",\n'
        '      "confidence": "high|medium|low",\n'
        '      "evidence": "[quote from document]",\n'
        '      "caveats": ""\n'
        "    }\n"
        "  ],\n"
        '  "action_summary": "[one paragraph in plain language for the resident]"\n'
        "}\n\n"
        "Important: never state or imply that a document is accepted by the agency. Use 'appears to satisfy' and 'likely matches' only.\n"
        "Always show caveats when confidence is not high.\n"
        "If the notice image is blurry or you cannot clearly read the text, set notice_summary fields to UNCERTAIN - do not guess.";
  }

  /// Track B: BPS Enrollment Packet Checker
  static String trackB({required List<String> documentLabels}) {
    final documentList = documentLabels
        .asMap()
        .entries
        .map((e) => '${e.key + 1}. ${e.value}')
        .join('\n');

    return "You are helping a family prepare their Boston Public Schools registration packet.\n\n"
        "The BPS registration checklist requires:\n"
        "- Proof of child's age (birth certificate or passport)\n"
        "- TWO proofs of Boston residency from DIFFERENT categories.\n"
        "  Valid categories: lease/deed, utility bill, bank statement, government mail, employer letter, notarized affidavit.\n"
        "  Two documents from the same category count as only ONE proof.\n"
        "  If both documents are leases, set duplicate_category_flag to true.\n"
        "- Current immunization record\n"
        "- Grade-level indicator (most recent report card or transcript, if applicable)\n\n"
        "The family has uploaded the following documents (images attached):\n"
        "$documentList\n\n"
        "Return JSON:\n"
        "{\n"
        '  "requirements": [\n'
        "    {\n"
        '      "requirement": "",\n'
        '      "status": "satisfied|questionable|missing",\n'
        '      "matched_document": "[document name or MISSING]",\n'
        '      "evidence": "[quote or observation]",\n'
        '      "notes": ""\n'
        "    }\n"
        "  ],\n"
        '  "duplicate_category_flag": true|false,\n'
        '  "duplicate_category_explanation": "",\n'
        '  "family_summary": "[plain language: what to bring, what to replace]"\n'
        "}\n\n"
        "If a document is a phone bill or cell phone statement, set its residency status to questionable - acceptance varies by BPS policy.\n"
        "Important: never state that the packet guarantees registration or school assignment.";
  }

  /// Generate document labels for the prompt
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
}

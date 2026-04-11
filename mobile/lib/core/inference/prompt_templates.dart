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

  /// Shorter Track A prompt for OCR-only pipeline (keeps prompt under llama nBatch).
  static String trackAOcrOnly({required List<String> documentLabels}) {
    final list = documentLabels
        .asMap()
        .entries
        .map((e) => '${e.key + 1}. ${e.value}')
        .join('\n');

    return 'You help a resident with a government benefit notice and proof '
        'documents (e.g. SNAP verification). Only OCR text is below; it may '
        'contain errors.\n\n'
        'Supporting docs (labels):\n$list\n\n'
        'Steps: (1) Read the notice — requested proof categories, deadline, '
        'consequence. (2) Map each document to a category; use likely_satisfies / '
        'likely_does_not_satisfy / missing / uncertain. (3) Return ONLY valid JSON '
        '(no markdown).\n\n'
        '{"notice_summary":{"requested_categories":[],"deadline":"","consequence":""},'
        '"proof_pack":[{"category":"","matched_document":"[name or MISSING]",'
        '"assessment":"likely_satisfies|likely_does_not_satisfy|missing|uncertain",'
        '"confidence":"high|medium|low","evidence":"","caveats":""}],'
        '"action_summary":""}\n\n'
        'The action_summary string in that JSON: 2–4 sentences, concrete next steps. '
        'Never put action_summary outside the braces — no line like action_summary: '
        'after the final }.\n\n'
        'Never imply the agency accepted documents. If the notice is unreadable, '
        'use UNCERTAIN in notice fields; do not guess.\n\n'
        'Reply with only the JSON object. No markdown fences, no commentary before '
        'or after. Escape any line breaks inside string values as \\n.\n'
        'Use real deadline text from the notice when present; if truly missing, use '
        'empty string "" for deadline and consequence — never bracket placeholders '
        'like [Not specified].\n'
        'Deadline: in the Government notice OCR, copy any response due date / '
        '"submit by" / "return by" line verbatim into deadline; leave "" only if '
        'no date appears there. Do not set consequence to "unreadable" unless the '
        'notice body is illegible — if unclear, use "".';
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

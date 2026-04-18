/// Result models for Track A (SNAP Benefits)

enum ConfidenceLevel { high, medium, low, uncertain }

enum AssessmentLabel {
  likelySatisfies,
  likelyDoesNotSatisfy,
  missing,
  uncertain
}

class NoticeSummary {
  final List<String> requestedCategories;
  final String deadline;
  final String consequence;

  const NoticeSummary({
    required this.requestedCategories,
    required this.deadline,
    required this.consequence,
  });

  /// True only when the model explicitly abstains ([UNCERTAIN]). Empty deadline
  /// means "not extracted" — show proof pack without the red unclear banner.
  bool get isUncertain => deadline == 'UNCERTAIN';

  factory NoticeSummary.fromJson(Map<String, dynamic> json) {
    return NoticeSummary(
      requestedCategories: List<String>.from(json['requested_categories'] ?? []),
      deadline: _normalizeNoticeDeadline(json['deadline']),
      consequence: _normalizeNoticeConsequence(json['consequence']),
    );
  }

  /// Placeholders → UNCERTAIN; null/empty → "" (partial notice read, no banner).
  static String _normalizeNoticeDeadline(Object? v) {
    if (v == null) return '';
    final s = v.toString().trim();
    if (s.isEmpty) return '';
    final lower = s.toLowerCase();
    if (lower == 'uncertain' ||
        lower.contains('not specified') ||
        lower == 'n/a' ||
        lower == 'tbd' ||
        lower == 'unknown') {
      return 'UNCERTAIN';
    }
    return s;
  }

  static String _normalizeNoticeConsequence(Object? v) {
    if (v == null) return '';
    final s = v.toString().trim();
    final lower = s.toLowerCase();
    if (lower == 'unreadable' ||
        lower == 'uncertain' ||
        lower.contains('not specified') ||
        lower == 'n/a' ||
        lower == 'tbd' ||
        lower == 'unknown') {
      return '';
    }
    return s;
  }
}

class ProofPackItem {
  final String category;
  final String matchedDocument;
  final AssessmentLabel assessment;
  final ConfidenceLevel confidence;
  final String evidence;
  final String caveats;

  const ProofPackItem({
    required this.category,
    required this.matchedDocument,
    required this.assessment,
    required this.confidence,
    required this.evidence,
    required this.caveats,
  });

  bool get isMissing => matchedDocument == 'MISSING';

  factory ProofPackItem.fromJson(Map<String, dynamic> json) {
    return ProofPackItem(
      category: json['category'] ?? '',
      matchedDocument: json['matched_document'] ?? 'MISSING',
      assessment: _parseAssessment(json['assessment']),
      confidence: _parseConfidence(json['confidence']),
      evidence: json['evidence'] ?? '',
      caveats: json['caveats'] ?? '',
    );
  }

  static AssessmentLabel _parseAssessment(String? value) {
    switch (value) {
      case 'likely_satisfies':
        return AssessmentLabel.likelySatisfies;
      case 'likely_does_not_satisfy':
        return AssessmentLabel.likelyDoesNotSatisfy;
      case 'missing':
        return AssessmentLabel.missing;
      default:
        return AssessmentLabel.uncertain;
    }
  }

  static ConfidenceLevel _parseConfidence(String? value) {
    switch (value) {
      case 'high':
        return ConfidenceLevel.high;
      case 'medium':
        return ConfidenceLevel.medium;
      case 'low':
        return ConfidenceLevel.low;
      default:
        return ConfidenceLevel.uncertain;
    }
  }
}

class TrackAResult {
  final NoticeSummary noticeSummary;
  final List<ProofPackItem> proofPack;
  final String actionSummary;

  const TrackAResult({
    required this.noticeSummary,
    required this.proofPack,
    required this.actionSummary,
  });

  /// Highest `N` in labels like `Document N` from the upload UI (one image per label).
  static int maxUploadedDocumentSlot(List<String> supportingDocumentLabels) {
    var maxN = 0;
    for (final label in supportingDocumentLabels) {
      final m = RegExp(r'document\s*(\d+)', caseSensitive: false).firstMatch(label);
      if (m != null) {
        final n = int.tryParse(m.group(1)!) ?? 0;
        if (n > maxN) maxN = n;
      }
    }
    if (maxN == 0) return supportingDocumentLabels.length;
    return maxN;
  }

  /// True if [text] references `Document K` for any `K` greater than [maxSlot].
  static bool referencesDocumentSlotAbove(String text, int maxSlot) {
    if (maxSlot <= 0) return false;
    for (final m
        in RegExp(r'\bdocument\s*(\d+)\b', caseSensitive: false).allMatches(text)) {
      final n = int.tryParse(m.group(1)!) ?? 0;
      if (n > maxSlot) return true;
    }
    return false;
  }

  /// Drops hallucinated ties to non-uploaded slots (e.g. "Document 2" when only
  /// one supporting photo was sent). Rows are turned into [AssessmentLabel.missing]
  /// with [matchedDocument] `MISSING` so the UI matches what the resident uploaded.
  TrackAResult withProofPackClampedToUploadedSlots(
    List<String> supportingDocumentLabels,
  ) {
    if (supportingDocumentLabels.isEmpty) return this;
    final maxSlot = maxUploadedDocumentSlot(supportingDocumentLabels);
    if (maxSlot <= 0) return this;

    var changed = false;
    final adjusted = <ProofPackItem>[];
    for (final item in proofPack) {
      final blob = '${item.matchedDocument}\n${item.evidence}';
      if (!referencesDocumentSlotAbove(blob, maxSlot)) {
        adjusted.add(item);
        continue;
      }
      changed = true;
      const caveat =
          'Adjusted on-device: this line referred to a document slot you did not '
          'upload (for example Document 2 with only one supporting photo).';
      adjusted.add(
        ProofPackItem(
          category: item.category,
          matchedDocument: 'MISSING',
          assessment: AssessmentLabel.missing,
          confidence: ConfidenceLevel.uncertain,
          evidence: '',
          caveats: item.caveats.trim().isEmpty
              ? caveat
              : '${item.caveats.trim()}\n\n$caveat',
        ),
      );
    }

    if (!changed) return this;

    // Caller should refresh [actionSummary] via [LabelFormatter.synthesizeTrackAActionSummary]
    // when the proof pack changes (avoids importing LabelFormatter here — it imports this file).
    return TrackAResult(
      noticeSummary: noticeSummary,
      proofPack: adjusted,
      actionSummary: actionSummary,
    );
  }

  factory TrackAResult.fromJson(Map<String, dynamic> json) {
    return TrackAResult(
      noticeSummary: NoticeSummary.fromJson(json['notice_summary'] ?? {}),
      proofPack: (json['proof_pack'] as List? ?? [])
          .whereType<Map>()
          .map((item) => ProofPackItem.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      actionSummary: _firstNonEmptyString(json, const [
        'action_summary',
        'actionSummary',
        'next_steps',
        'what_to_do_next',
        'summary',
        'resident_summary',
      ]),
    );
  }

  static String _firstNonEmptyString(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    for (final k in keys) {
      final v = json[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }
}

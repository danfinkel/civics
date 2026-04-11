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

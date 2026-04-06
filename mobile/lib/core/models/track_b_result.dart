/// Result models for Track B (School Enrollment)

import 'track_a_result.dart';

enum RequirementStatus { satisfied, questionable, missing }

class RequirementResult {
  final String requirement;
  final RequirementStatus status;
  final String matchedDocument;
  final String evidence;
  final String notes;
  final ConfidenceLevel confidence;

  const RequirementResult({
    required this.requirement,
    required this.status,
    required this.matchedDocument,
    required this.evidence,
    required this.notes,
    required this.confidence,
  });

  factory RequirementResult.fromJson(Map<String, dynamic> json) {
    return RequirementResult(
      requirement: json['requirement'] ?? '',
      status: _parseStatus(json['status']),
      matchedDocument: json['matched_document'] ?? 'MISSING',
      evidence: json['evidence'] ?? '',
      notes: json['notes'] ?? '',
      confidence: _parseConfidence(json['confidence']),
    );
  }

  static RequirementStatus _parseStatus(String? value) {
    switch (value) {
      case 'satisfied':
        return RequirementStatus.satisfied;
      case 'questionable':
        return RequirementStatus.questionable;
      default:
        return RequirementStatus.missing;
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

class TrackBResult {
  final List<RequirementResult> requirements;
  final bool duplicateCategoryFlag;
  final String duplicateCategoryExplanation;
  final String familySummary;

  const TrackBResult({
    required this.requirements,
    required this.duplicateCategoryFlag,
    required this.duplicateCategoryExplanation,
    required this.familySummary,
  });

  ConfidenceLevel get overallConfidence {
    if (requirements.isEmpty) return ConfidenceLevel.uncertain;

    final hasLow = requirements.any((r) => r.confidence == ConfidenceLevel.low);
    final hasUncertain =
        requirements.any((r) => r.confidence == ConfidenceLevel.uncertain);
    final allHigh =
        requirements.every((r) => r.confidence == ConfidenceLevel.high);

    if (allHigh) return ConfidenceLevel.high;
    if (hasLow || hasUncertain) return ConfidenceLevel.low;
    return ConfidenceLevel.medium;
  }

  factory TrackBResult.fromJson(Map<String, dynamic> json) {
    return TrackBResult(
      requirements: (json['requirements'] as List? ?? [])
          .map((item) => RequirementResult.fromJson(item))
          .toList(),
      duplicateCategoryFlag: json['duplicate_category_flag'] ?? false,
      duplicateCategoryExplanation:
          json['duplicate_category_explanation'] ?? '',
      familySummary: json['family_summary'] ?? '',
    );
  }
}

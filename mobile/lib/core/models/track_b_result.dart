/// Result models for Track B (School Enrollment)

import 'package:flutter/foundation.dart';

import '../utils/eval_mode.dart';
import '../utils/label_formatter.dart';
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

  /// Rows for UI (same as [requirements] after alignment; no status rewriting).
  ///
  /// Packet-level copy (hero, “N of M satisfied”) still reflects how many rows are
  /// [satisfied]; rows that are [questionable] or [missing] stay that way. A clean
  /// immunization can show a green check even when age or residency are questionable.
  List<RequirementResult> get requirementsForDisplay =>
      List<RequirementResult>.from(requirements);

  /// Count of [RequirementStatus.satisfied] rows (same basis as [requirementsForDisplay]).
  int get satisfiedCount => requirements
      .where((r) => r.status == RequirementStatus.satisfied)
      .length;

  /// Same as [satisfiedCount] for Track B; kept for eval logs and API stability.
  int get satisfiedCountRaw =>
      requirements.where((r) => r.status == RequirementStatus.satisfied).length;

  ConfidenceLevel get overallConfidence {
    final rows = requirementsForDisplay;
    if (rows.isEmpty) return ConfidenceLevel.uncertain;

    final hasLow = rows.any((r) => r.confidence == ConfidenceLevel.low);
    final hasUncertain =
        rows.any((r) => r.confidence == ConfidenceLevel.uncertain);
    final allHigh = rows.every((r) => r.confidence == ConfidenceLevel.high);

    if (allHigh) return ConfidenceLevel.high;
    if (hasLow || hasUncertain) return ConfidenceLevel.low;
    return ConfidenceLevel.medium;
  }

  factory TrackBResult.fromJson(Map<String, dynamic> json) {
    final reqList = json['requirements'];
    final requirements = <RequirementResult>[];
    if (reqList is List) {
      for (final item in reqList) {
        if (item is Map) {
          requirements.add(
            RequirementResult.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    return TrackBResult(
      requirements: requirements,
      duplicateCategoryFlag: json['duplicate_category_flag'] ?? false,
      duplicateCategoryExplanation:
          json['duplicate_category_explanation'] ?? '',
      familySummary: json['family_summary'] ?? '',
    );
  }

  /// One checklist row per uploaded slot (same order as [slotDescriptions]).
  ///
  /// Drops extra model rows (e.g. prompt echo / duplicate OCR lines) and inserts
  /// [missing] rows when the model never matched a slot (common for immunization).
  factory TrackBResult.alignToUploadSlots(
    TrackBResult parsed, {
    required List<String> slotDescriptions,
  }) {
    if (slotDescriptions.isEmpty) return parsed;
    final cleaned = parsed.requirements
        .where((r) => !_trackBModelRowLooksLikePromptEcho(r))
        .toList();
    if (kInferenceDiagnostics &&
        cleaned.length != parsed.requirements.length) {
      debugPrint(
        '[TrackB][align] stripped ${parsed.requirements.length - cleaned.length} '
        'prompt-echo row(s); ${cleaned.length} row(s) before slot mapping',
      );
    }
    final aligned = _alignTrackBRequirementsToSlots(
      cleaned,
      slotDescriptions,
    );
    return TrackBResult(
      requirements: aligned,
      duplicateCategoryFlag: parsed.duplicateCategoryFlag,
      duplicateCategoryExplanation: parsed.duplicateCategoryExplanation,
      familySummary: parsed.familySummary,
    );
  }

  /// When the model set [duplicateCategoryFlag] **or** on-device logic detects two
  /// satisfied residency uploads that both look like lease/rental (same BPS category),
  /// downgrade [residency_proof_2] from satisfied → **questionable** and surface
  /// the duplicate banner so the hero cannot show “application verified” incorrectly.
  TrackBResult withResidencyProof2QuestionableWhenDuplicateCategory() {
    final inferredDup =
        _trackBInferSameLeaseCategoryResidencyDuplicate(requirements);
    final treatAsDuplicate = duplicateCategoryFlag || inferredDup;
    if (!treatAsDuplicate) return this;

    const inferredExplanation =
        'Both residency proofs look like lease or rental agreements, which is usually '
        'the same category for BPS.';

    var changed = false;
    final next = <RequirementResult>[];
    for (final r in requirements) {
      if (r.requirement == 'residency_proof_2' &&
          r.status == RequirementStatus.satisfied) {
        changed = true;
        next.add(
          RequirementResult(
            requirement: r.requirement,
            status: RequirementStatus.questionable,
            matchedDocument: r.matchedDocument,
            evidence: LabelFormatter.residencyProof2DuplicateCategoryEvidence,
            notes: r.notes,
            confidence: ConfidenceLevel.uncertain,
          ),
        );
      } else {
        next.add(r);
      }
    }

    final dupFlag = duplicateCategoryFlag || inferredDup;
    final dupExpl = duplicateCategoryExplanation.trim().isNotEmpty
        ? duplicateCategoryExplanation
        : (inferredDup ? inferredExplanation : duplicateCategoryExplanation);

    if (!changed) {
      return TrackBResult(
        requirements: requirements,
        duplicateCategoryFlag: dupFlag,
        duplicateCategoryExplanation:
            dupExpl.isNotEmpty ? dupExpl : duplicateCategoryExplanation,
        familySummary: familySummary,
      );
    }

    return TrackBResult(
      requirements: next,
      duplicateCategoryFlag: dupFlag,
      duplicateCategoryExplanation: dupExpl,
      familySummary: familySummary,
    );
  }

  /// Plain text for share sheet / clipboard (design spec: Save Summary / share).
  String toShareableText() {
    final b = StringBuffer()
      ..writeln('CivicLens — Boston Public Schools registration')
      ..writeln();

    for (final r in requirementsForDisplay) {
      final status = LabelFormatter.requirementStatusLabel(r.status.name);
      final name = trackBRequirementResidentTitle(r);
      b.writeln('• $name: $status');
      if (kEvalMode) {
        b.writeln('  Matched: ${r.matchedDocument}');
        if (r.evidence.isNotEmpty) {
          b.writeln('  Evidence: ${r.evidence}');
        }
      }
      b.writeln();
    }

    if (duplicateCategoryFlag) {
      final dup = LabelFormatter.duplicateCategoryUserMessage(
        duplicateCategoryExplanation,
      );
      final note = dup.isNotEmpty
          ? dup
          : 'Possible duplicate document categories.';
      b.writeln('Note: $note');
      b.writeln();
    }

    b
      ..writeln('What to bring')
      ..writeln('─────────────')
      ..writeln(displayFamilySummary);

    return b.toString().trim();
  }

  /// Model output or synthesized fallback when `family_summary` is empty.
  String get displayFamilySummary {
    final t = familySummary.trim();
    if (t.isNotEmpty) return t;
    return _synthesizeTrackBFamilySummary(this);
  }
}

final RegExp _trackBLeaseLikePattern = RegExp(
  r'lease|rental|tenant|lessor|landlord|sublease|sub-lease|residential agreement|'
  r'apartment\s*(?:#|number|no\.?)|unit\s*(?:#|number|no\.?)',
  caseSensitive: false,
);

/// Non-lease residency categories (only used to veto when [matched] does not
/// already look like a lease OCR line).
bool _trackBMatchedLineLooksLikeOtherResidencyCategory(String matchedLower) {
  return RegExp(
    r'utility|utilities|electric bill|gas bill|water bill|sewer|cable bill|'
    r'bank stmt|bank statement|paystub|pay stub|employer letter|'
    r'government mail|w-2|1099|mortgage stmt|mortgage statement|'
    r'affidavit|notarized',
    caseSensitive: false,
  ).hasMatch(matchedLower);
}

/// True when this row’s **matched_document** (OCR) is lease/rental-like.
///
/// The model often writes contradictory “different category” prose in
/// [RequirementResult.evidence] while [matchedDocument] is still the lease
/// header — we trust **matched** first so inference is not vetoed by evidence.
bool _trackBResidencyBlobLooksLikeLeaseCategory(RequirementResult r) {
  final m = r.matchedDocument.toLowerCase();
  final e = r.evidence.toLowerCase();
  if (m.trim().isEmpty && e.trim().isEmpty) return false;

  if (_trackBLeaseLikePattern.hasMatch(m)) {
    return true;
  }

  final blob = '$m $e'.trim();
  if (blob.isEmpty) return false;
  if (!_trackBLeaseLikePattern.hasMatch(blob)) return false;
  if (_trackBMatchedLineLooksLikeOtherResidencyCategory(m) &&
      !_trackBLeaseLikePattern.hasMatch(m)) {
    return false;
  }
  if (RegExp(
    r'utility|utilities|electric bill|gas bill|water bill|sewer|cable bill|'
    r'bank stmt|bank statement|paystub|pay stub|employer letter|'
    r'government mail|w-2|1099|mortgage stmt|mortgage statement',
    caseSensitive: false,
  ).hasMatch(blob)) {
    return false;
  }
  return true;
}

String _trackBNormalizeResidencyMatchKey(String s) {
  return s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}

Set<String> _trackBSignificantTokens(String normalized) {
  return normalized
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.length >= 4)
      .toSet();
}

/// True when both rows’ matched OCR is almost the same text (same lease pages
/// uploaded twice, or two crops of the same agreement).
bool _trackBResidencyMatchedDocsStronglySimilar(
  RequirementResult a,
  RequirementResult b,
) {
  final ma = _trackBNormalizeResidencyMatchKey(a.matchedDocument);
  final mb = _trackBNormalizeResidencyMatchKey(b.matchedDocument);
  if (ma.length < 14 || mb.length < 14) return false;
  if (ma == mb) return true;
  final shorter = ma.length <= mb.length ? ma : mb;
  final longer = ma.length > mb.length ? ma : mb;
  if (longer.contains(shorter) && shorter.length >= 20) return true;

  final ta = _trackBSignificantTokens(ma);
  final tb = _trackBSignificantTokens(mb);
  if (ta.isEmpty || tb.isEmpty) return false;
  final inter = ta.intersection(tb).length;
  final union = ta.union(tb).length;
  return union > 0 && inter >= 6 && inter / union >= 0.52;
}

/// Same BPS rule as [duplicateCategoryFlag] when the LLM forgets to set it: two
/// **satisfied** residency slots that both read as lease/rental **or** carry the
/// same lease OCR in [matchedDocument] while evidence claims a different category.
bool _trackBInferSameLeaseCategoryResidencyDuplicate(
  List<RequirementResult> requirements,
) {
  RequirementResult? r1;
  RequirementResult? r2;
  for (final r in requirements) {
    if (r.requirement == 'residency_proof_1') r1 = r;
    if (r.requirement == 'residency_proof_2') r2 = r;
  }
  if (r1 == null || r2 == null) return false;
  if (r1.status != RequirementStatus.satisfied ||
      r2.status != RequirementStatus.satisfied) {
    return false;
  }
  final lease1 = _trackBResidencyBlobLooksLikeLeaseCategory(r1);
  final lease2 = _trackBResidencyBlobLooksLikeLeaseCategory(r2);
  if (lease1 && lease2) return true;
  return _trackBResidencyMatchedDocsStronglySimilar(r1, r2) && (lease1 || lease2);
}

/// Rows where the model pasted **instructions** or OCR preamble into
/// [RequirementResult.requirement] — not real checklist items. They confuse
/// slot pooling (e.g. a bogus "satisfied" row stealing the immunization slot).
bool _trackBModelRowLooksLikePromptEcho(RequirementResult r) {
  final req = r.requirement.trim().toLowerCase();
  if (req.isEmpty) return false;
  if (req.contains('ocr from') && RegExp(r'\d').hasMatch(req) && req.contains('document')) {
    return true;
  }
  if (req.contains('duplicate_category_flag') ||
      req.contains('set duplicate_category')) {
    return true;
  }
  if (req.contains('two docs same category') && req.contains('only one proof')) {
    return true;
  }
  if (req.contains('return only valid json')) return true;
  return false;
}

/// Forces [r.requirement] to the canonical slug for [slotDescriptions] line
/// (Proof of Age, Residency 1/2, Immunization, …) so UI titles match upload
/// order even when OCR/model buckets mis-label a row (e.g. "Boston" on a vax card).
RequirementResult _rekeyRequirementToSlot(
  RequirementResult r,
  String slotDesc,
) {
  final key = _trackBSlotKeyFromDescription(slotDesc);
  if (key == null) return r;
  final canonical = switch (key) {
    'age' => 'proof_of_age',
    'res1' => 'residency_proof_1',
    'res2' => 'residency_proof_2',
    'imm' => 'immunization_record',
    'grade' => 'grade_indicator',
    _ => r.requirement,
  };
  return RequirementResult(
    requirement: canonical,
    status: r.status,
    matchedDocument: r.matchedDocument,
    evidence: r.evidence,
    notes: r.notes,
    confidence: r.confidence,
  );
}

List<RequirementResult> _alignTrackBRequirementsToSlots(
  List<RequirementResult> modelRows,
  List<String> slotDescriptions,
) {
  // Same count as uploads: trust model row order (matches document order in prompt).
  if (modelRows.length == slotDescriptions.length) {
    return List.generate(
      slotDescriptions.length,
      (i) => _rekeyRequirementToSlot(modelRows[i], slotDescriptions[i]),
    );
  }

  final pool = List<RequirementResult>.from(modelRows);
  final out = <RequirementResult>[];

  bool takeWhere(bool Function(RequirementResult) test) {
    final i = pool.indexWhere(test);
    if (i < 0) return false;
    out.add(pool.removeAt(i));
    return true;
  }

  bool takeBucketOrSlotMatch(String slotDesc, String want) {
    if (takeWhere((r) => _trackBModelRowBucket(r) == want)) return true;
    return takeWhere((r) => _rowLikelyMatchesSlotKey(r, slotDesc, want));
  }

  for (final desc in slotDescriptions) {
    final want = _trackBSlotKeyFromDescription(desc);
    if (want == null) {
      if (pool.isNotEmpty) {
        out.add(pool.removeAt(0));
      }
      continue;
    }

    var picked = false;
    if (want == 'age' || want == 'imm' || want == 'grade') {
      picked = takeBucketOrSlotMatch(desc, want);
    } else if (want == 'res1' || want == 'res2') {
      picked = takeBucketOrSlotMatch(desc, 'res');
    }

    if (!picked) {
      out.add(_trackBSyntheticMissing(want));
    }
  }

  for (var i = 0; i < out.length; i++) {
    out[i] = _rekeyRequirementToSlot(out[i], slotDescriptions[i]);
  }
  return out;
}

String? _trackBSlotKeyFromDescription(String line) {
  final l = line.toLowerCase();
  if (l.contains('grade indicator') || l.startsWith('grade')) return 'grade';
  if (l.contains('immunization')) return 'imm';
  if (l.contains('residency proof 2')) return 'res2';
  if (l.contains('residency proof 1')) return 'res1';
  if (l.contains('proof of age')) return 'age';
  return null;
}

String? _trackBModelRowBucket(RequirementResult r) {
  final b = '${r.requirement} ${r.matchedDocument} ${r.evidence}'.toLowerCase();
  if (RegExp(
    r'immuniz|vaccin|vaccination|shot record|school immunization|'
    r'vaccine administration|given\s*date|route\s*site|'
    r'\bdtap\b|\btdap\b|\bmmr\b|'
    r'varicella|hepatitis|hib\b|polio|rotavirus|mening|series of|doses?\b|'
    r'certificate of immun',
  ).hasMatch(b)) {
    return 'imm';
  }
  if (RegExp(r'\bgrade\b|report card|transcript').hasMatch(b)) return 'grade';
  if (RegExp(
    r'\bbirth\b|passport|proof of.?age|child.?age|certificate of live',
  ).hasMatch(b)) {
    return 'age';
  }
  // Do not use "boston" alone — immunization and school forms often mention the city.
  if (RegExp(
    r'resid|lease|utility|deed|mortgage|affidavit|tenant|lessor|rental',
  ).hasMatch(b)) {
    return 'res';
  }
  return null;
}

bool _rowLikelyMatchesSlotKey(
  RequirementResult r,
  String slotDesc,
  String want,
) {
  final blob =
      '${r.requirement} ${r.matchedDocument} ${r.evidence}'.toLowerCase();
  return switch (want) {
    'age' => RegExp(r'birth|age|passport|child|certificate').hasMatch(blob),
    'imm' => RegExp(
        r'immuniz|vaccin|certificate of immun|school immunization|'
        r'given\s*date|vaccine administration|'
        r'\bshots?\b|shot record|vaccination|booster|\binjection\b|'
        r'\bdtap\b|\btdap\b|\bmmr\b|'
        r'varicella|hepatitis|hib\b|polio',
      ).hasMatch(blob),
    'grade' => RegExp(r'grade|report|transcript').hasMatch(blob),
    'res' => RegExp(r'lease|resid|utility|rent|tenant|deed|mortgage').hasMatch(
        blob,
      ),
    _ => false,
  };
}

RequirementResult _trackBSyntheticMissing(String slotKey) {
  final req = switch (slotKey) {
    'age' => 'proof_of_age',
    'res1' => 'residency_proof_1',
    'res2' => 'residency_proof_2',
    'imm' => 'immunization_record',
    'grade' => 'grade_indicator',
    _ => 'requirement',
  };
  return RequirementResult(
    requirement: req,
    status: RequirementStatus.missing,
    matchedDocument: 'MISSING',
    evidence: '',
    notes: '',
    confidence: ConfidenceLevel.uncertain,
  );
}

/// Resident-facing checklist title; repairs prompt leakage in `requirement`.
String trackBRequirementResidentTitle(RequirementResult r) {
  final raw = r.requirement.trim();
  if (raw.isEmpty || _trackBRequirementTextLooksCorrupted(raw)) {
    return _inferTrackBTitleFromDocuments(r.matchedDocument, r.evidence);
  }
  final lower = raw.toLowerCase();
  if (lower.contains('two boston residency') &&
      lower.contains('different categor')) {
    return 'Boston residency proof';
  }
  if (lower.contains('child age proof') ||
      (lower.contains('birth cert') && lower.contains('passport'))) {
    return "Proof of child's age";
  }
  return LabelFormatter.requirementLabel(raw);
}

/// Why this row is not a green check (questionable / needs staff judgment).
String trackBQuestionableResidentExplanation(RequirementResult r) {
  if (r.status != RequirementStatus.questionable) return '';

  String cleaned(String s) {
    var t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.length < 12) return '';
    if (t.contains('"requirement"') || t.contains('"proof_pack"')) return '';
    return t;
  }

  final ev = cleaned(r.evidence);
  final notes = cleaned(r.notes);
  final pick = ev.isNotEmpty ? ev : notes;
  if (pick.isNotEmpty && !_looksLikeOcrGarbageLine(pick)) {
    if (pick.length <= 220) return pick;
    return '${pick.substring(0, 217).trim()}…';
  }

  return 'This does not get a green check because on-device review is not fully '
      'confident that BPS will count this upload for this checklist item. Your '
      'document may still be fine—bring the original and ask registration staff.';
}

/// Line under each checklist row: friendly label when `matched_document` is OCR slop.
String trackBMatchedDocumentSubtitle(RequirementResult r) {
  final m = r.matchedDocument.trim();
  if (m.isEmpty || m == 'MISSING') {
    return m == 'MISSING' ? '' : 'No document matched';
  }
  if (_looksLikeOcrGarbageLine(m)) {
    final kind = _inferUploadedDocKind(m, r.evidence);
    return '$kind · On-device text was too messy to show—staff read your original.';
  }
  if (m.length > 72) return '${m.substring(0, 69).trim()}…';
  return m;
}

/// Short, actionable “Next steps” copy (does not repeat the long summary).
String trackBNextStepsLead(TrackBResult r) {
  final rows = r.requirementsForDisplay;
  final hasQ = rows.any((x) => x.status == RequirementStatus.questionable);
  final hasM = rows.any((x) => x.status == RequirementStatus.missing);
  final buf = StringBuffer()
    ..writeln(
      'Bring paper originals of every document you photographed to registration. '
      'Photos can be misread; staff compare originals to the official checklist.',
    );
  if (hasQ) {
    buf.writeln(
      'For rows marked “check with your office,” ask BPS whether that upload '
      'counts—this app only guesses from your photos.',
    );
  }
  if (hasM) {
    buf.writeln(
      'You still have checklist gaps—bring any missing proof you can obtain '
      'before your appointment.',
    );
  }
  if (!hasQ && !hasM) {
    buf.writeln(
      'If everything shows as met, you are in good shape for review—still bring '
      'originals in case staff want to re-check.',
    );
  }
  return buf.toString().trim();
}

bool _looksLikeOcrGarbageLine(String s) {
  if (s.length <= 90) return false;
  final letters = s.replaceAll(RegExp(r'[^A-Za-z]'), '');
  if (letters.isEmpty) return s.length > 140;
  final upperCount = letters.replaceAll(RegExp(r'[^A-Z]'), '').length;
  final upperRatio = upperCount / letters.length;
  if (s.length > 120 && upperRatio > 0.42) return true;
  if (s.length > 220) return true;
  final u = s.toUpperCase();
  if ('RESIDENTIAL LEASE'.allMatches(u).length >= 2) return true;
  if ('CERTIFICATE OF LIVE BIRTH'.allMatches(u).length >= 2) return true;
  final tokens = s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  if (tokens > 28) return true;
  return false;
}

String _inferUploadedDocKind(String matched, String evidence) {
  final b = '${matched.toLowerCase()} ${evidence.toLowerCase()}';
  if (RegExp(r'birth|passport|live birth|certificate').hasMatch(b)) {
    return 'Birth / age document';
  }
  if (RegExp(r'lease|residen|rental|tenant').hasMatch(b)) {
    return 'Lease / residency document';
  }
  if (b.contains('immuniz')) return 'Immunization record';
  if (RegExp(r'utility|bill|bank').hasMatch(b)) {
    return 'Residency-related document';
  }
  return 'Uploaded document';
}

List<String> _uniqueTitlesPreserveOrder(Iterable<RequirementResult> rows) {
  final seen = <String>{};
  final out = <String>[];
  for (final row in rows) {
    final t = trackBRequirementResidentTitle(row);
    if (t.isEmpty) continue;
    if (seen.add(t)) out.add(t);
  }
  return out;
}

bool _trackBRequirementTextLooksCorrupted(String s) {
  final l = s.toLowerCase();
  const needles = [
    'ocr from',
    'document(s)',
    'may have errors',
    'duplicate_category',
    'two docs same',
    'same category = only',
    'set duplicate',
    'return json',
    'plain language:',
    'if a document is a phone bill',
    'requirements satisfied',
    'registration packet —',
    '"requirements"',
    'bps registration',
  ];
  return needles.any(l.contains);
}

String _inferTrackBTitleFromDocuments(String matched, String evidence) {
  final b = '${matched.toLowerCase()} ${evidence.toLowerCase()}';
  if (RegExp(r'birth|passport|live birth|age proof|child.?age').hasMatch(b)) {
    return "Proof of child's age";
  }
  if (RegExp(
    r'lease|residen|utility|deed|bank stmt|bank statement|mortgage|affidavit|employer|gov mail|government mail',
  ).hasMatch(b)) {
    return 'Boston residency proof';
  }
  if (b.contains('immuniz')) return 'Immunization record';
  if (RegExp(r'grade|report card|transcript').hasMatch(b)) {
    return 'Grade indicator (if applicable)';
  }
  return 'Registration checklist item';
}

String _synthesizeTrackBFamilySummary(TrackBResult r) {
  final buf = StringBuffer();

  final rows = r.requirementsForDisplay;
  final sat =
      rows.where((x) => x.status == RequirementStatus.satisfied).toList();
  final quest =
      rows.where((x) => x.status == RequirementStatus.questionable).toList();
  final miss =
      rows.where((x) => x.status == RequirementStatus.missing).toList();

  buf.writeln('Bring these originals to registration (paper copies):');
  buf.writeln();

  if (sat.isNotEmpty) {
    buf.writeln('Looks good on this device for:');
    for (final t in _uniqueTitlesPreserveOrder(sat)) {
      buf.writeln('• $t');
    }
    buf.writeln();
  }

  if (quest.isNotEmpty) {
    buf.writeln('Ask BPS staff to confirm (not a green check here):');
    for (final t in _uniqueTitlesPreserveOrder(quest)) {
      buf.writeln('• $t');
    }
    buf.writeln();
  }

  if (miss.isNotEmpty) {
    buf.writeln('Not found in your uploads—bring if you have them:');
    for (final t in _uniqueTitlesPreserveOrder(miss)) {
      buf.writeln('• $t');
    }
    buf.writeln();
  }

  if (r.duplicateCategoryFlag) {
    final dup = LabelFormatter.duplicateCategoryUserMessage(
      r.duplicateCategoryExplanation,
    );
    if (dup.isNotEmpty) {
      buf.writeln(dup);
      buf.writeln();
    }
  }

  buf.write(
    'BPS staff make the final decision. This list is from CivicLens on your '
    'phone—it is not an approval letter.',
  );

  return buf.toString().trim();
}

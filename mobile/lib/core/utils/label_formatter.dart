import '../models/track_a_result.dart';

/// Maps raw model / JSON labels to resident-facing copy.
class LabelFormatter {
  LabelFormatter._();

  static String assessmentLabel(String? raw) {
    switch (raw?.toLowerCase().trim()) {
      case 'likely_satisfies':
        return 'Appears to meet this requirement';
      case 'likely_does_not_satisfy':
        return 'May not meet this requirement';
      case 'insufficient_information':
        return 'Unclear — needs review';
      case 'missing':
        return 'Not found in your documents';
      case 'questionable':
        return 'Accepted by some offices — check with yours';
      case 'residency_ambiguous':
        return 'Acceptance varies by office';
      case 'invalid_proof':
        return 'This type of document is not accepted';
      case 'same_residency_category_duplicate':
        return 'Two leases (or two documents of the same type) count as one '
            'proof — you need a different category of document.';
      case 'satisfied':
        return 'Looks good';
      case 'uncertain':
        return 'Unclear — needs review';
      default:
        final s = raw?.trim() ?? '';
        return s.isEmpty ? 'Unknown' : raw!;
    }
  }

  /// Short status for compact chips (Track A proof pack).
  static String assessmentChipTrackA(AssessmentLabel label) {
    switch (label) {
      case AssessmentLabel.likelySatisfies:
        return 'Looks good';
      case AssessmentLabel.likelyDoesNotSatisfy:
        return 'May not meet';
      case AssessmentLabel.missing:
        return 'Not found';
      case AssessmentLabel.uncertain:
        return 'Needs review';
    }
  }

  static String requirementLabel(String? raw) {
    switch (raw?.toLowerCase().trim()) {
      case 'proof_of_age':
        return 'Proof of Age';
      case 'residency_proof_1':
        return 'Residency Proof (1 of 2)';
      case 'residency_proof_2':
        return 'Residency Proof (2 of 2)';
      case 'immunization_record':
        return 'Immunization Record';
      case 'grade_indicator':
        return 'Grade Indicator (if applicable)';
      case 'earned_income':
        return 'Earned Income';
      case 'residency':
        return 'Proof of Residency';
      case 'household_expenses':
        return 'Household Expenses';
      default:
        final s = raw?.trim() ?? '';
        return s.isEmpty ? 'Requirement' : s;
    }
  }

  static bool isHighConfidence(String? raw) =>
      raw?.toLowerCase().trim() == 'high';

  /// Track A [AssessmentLabel] → resident-facing assessment phrase.
  static String assessmentForTrackA(AssessmentLabel label) {
    switch (label) {
      case AssessmentLabel.likelySatisfies:
        return assessmentLabel('likely_satisfies');
      case AssessmentLabel.likelyDoesNotSatisfy:
        return assessmentLabel('likely_does_not_satisfy');
      case AssessmentLabel.missing:
        return assessmentLabel('missing');
      case AssessmentLabel.uncertain:
        return assessmentLabel('uncertain');
    }
  }

  /// Track B row status from [RequirementStatus.name] (`satisfied` / `questionable` / `missing`).
  static String requirementStatusLabel(String statusName) {
    switch (statusName) {
      case 'satisfied':
        return assessmentLabel('satisfied');
      case 'questionable':
        return assessmentLabel('questionable');
      case 'missing':
        return assessmentLabel('missing');
      default:
        return assessmentLabel('missing');
    }
  }

  /// Human-readable consequence line under the Track A deadline (model may send a code or sentence).
  static String noticeConsequenceLabel(String? raw) {
    final t = raw?.trim() ?? '';
    if (t.isEmpty) return '';
    switch (t.toLowerCase()) {
      case 'case_closure':
        return 'Your benefits could be stopped if you do not respond in time.';
      default:
        return t;
    }
  }

  /// Richer copy for the red deadline banner: lead + what happens + how to get help.
  static String noticeConsequenceExpanded(String? raw) {
    final t = raw?.trim() ?? '';
    final lower = t.toLowerCase();

    String lead;
    if (t.isEmpty) {
      lead =
          'If you do not respond by the deadline, the agency may change your case or benefits based on the rules described in your notice.';
    } else if (lower == 'case_closure') {
      lead =
          'Your benefits could be stopped or your case closed if the office does not receive what it asked for by the date above.';
    } else if (lower.contains('interrupt') && lower.contains('benefit')) {
      lead =
          'The notice warns that your benefits could be interrupted, reduced, or stopped if you do not send the requested proof in time.';
    } else if (t.length < 120) {
      lead =
          'The notice describes what can happen if you miss the deadline: $t';
    } else {
      lead = t;
    }

    const tail =
        '\n\nIf you cannot meet this date or are not sure what to send, contact the office listed on your notice right away. Many offices can explain what counts as proof or discuss extensions.';
    return '$lead$tail';
  }

  /// When the model omits `action_summary`, build concrete next steps for residents.
  static String synthesizeTrackAActionSummary(TrackAResult r) {
    final buf = StringBuffer();
    final pack = r.proofPackDeduplicatedByCategory;
    final missing = pack
        .where(
          (i) => i.isMissing || i.assessment == AssessmentLabel.missing,
        )
        .toList();
    if (missing.isNotEmpty) {
      final names =
          missing.map((e) => requirementLabel(e.category)).join(', ');
      buf.writeln(
        'Gather and submit the missing proof for: $names. Use the method your notice describes (online upload, mail, or in-person).',
      );
    }

    final uncertain = pack
        .where((i) => i.assessment == AssessmentLabel.uncertain)
        .toList();
    if (uncertain.isNotEmpty) {
      buf.writeln(
        'Some items need a second look—consider clearer photos or alternate documents if the office rejects what you have.',
      );
    }

    final ns = r.noticeSummary;
    if (ns.deadline.isNotEmpty && !ns.isUncertain) {
      buf.writeln(
        'Aim to send everything before ${ns.deadline}. Keep copies of what you submit.',
      );
    } else {
      buf.writeln(
        'Keep copies of anything you send. If a deadline is on your notice, treat that as your target date.',
      );
    }

    buf.write(
      'Questions? Use the phone number or address on your notice—the office handling your case can confirm what they still need.',
    );

    return buf.toString().trim();
  }

  /// Shown as [RequirementResult.evidence] when duplicate-category rules demote
  /// “Residency Proof 2” from satisfied → questionable.
  static const String residencyProof2DuplicateCategoryEvidence =
      'BPS counts two documents from the same residency category (for example, two '
      'leases) as only one proof. This upload does not satisfy your second proof '
      'until you add something from a different category (see the yellow note above).';

  /// Concrete examples for the duplicate-residency banner (appended when missing).
  static const String duplicateResidencySecondProofAlternatives =
      'For a second Boston residency proof, bring something from a different category '
      'than your lease—such as a recent utility bill, bank statement, official '
      'government mail with your address, an employer letter on letterhead, or a '
      'notarized residency affidavit. Ask BPS registration if you are unsure what '
      'they will accept.';

  static bool _duplicateMessageAlreadyListsAlternatives(String body) {
    final l = body.toLowerCase();
    return l.contains('utility bill') ||
        l.contains('bank statement') ||
        l.contains('notarized');
  }

  /// Duplicate-banner explanation may be a raw enum-like string from the model.
  static String duplicateCategoryUserMessage(String? raw) {
    final t = raw?.trim() ?? '';
    final body = t.isEmpty
        ? assessmentLabel('same_residency_category_duplicate')
        : assessmentLabel(t);
    if (_duplicateMessageAlreadyListsAlternatives(body)) return body;
    return '$body\n\n$duplicateResidencySecondProofAlternatives';
  }
}

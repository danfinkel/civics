import 'package:civiclens/core/utils/label_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:civiclens/core/models/track_a_result.dart';

void main() {
  group('TrackAResult proof pack clamp', () {
    test('maxUploadedDocumentSlot parses Document N from labels', () {
      expect(TrackAResult.maxUploadedDocumentSlot(const ['Document 1']), 1);
      expect(
        TrackAResult.maxUploadedDocumentSlot(const ['Document 1', 'Document 2']),
        2,
      );
      expect(TrackAResult.maxUploadedDocumentSlot(const ['Pay stub']), 1);
    });

    test('referencesDocumentSlotAbove', () {
      expect(TrackAResult.referencesDocumentSlotAbove('See Document 2', 1), isTrue);
      expect(
        TrackAResult.referencesDocumentSlotAbove('Document 1 only', 2),
        isFalse,
      );
      expect(TrackAResult.referencesDocumentSlotAbove('document 3', 2), isTrue);
      expect(TrackAResult.referencesDocumentSlotAbove('', 1), isFalse);
    });

    test('withProofPackClamped coerces row citing Document 2 when only slot 1', () {
      const ns = NoticeSummary(
        requestedCategories: <String>[],
        deadline: '',
        consequence: '',
      );
      final row1 = ProofPackItem(
        category: 'Income',
        matchedDocument: 'Pay stub',
        assessment: AssessmentLabel.likelySatisfies,
        confidence: ConfidenceLevel.high,
        evidence: 'OCR from Document 1',
        caveats: '',
      );
      final row2 = ProofPackItem(
        category: 'Rent',
        matchedDocument: 'Lease',
        assessment: AssessmentLabel.likelySatisfies,
        confidence: ConfidenceLevel.medium,
        evidence: 'From Document 2 header',
        caveats: 'Prior note',
      );
      final r = TrackAResult(
        noticeSummary: ns,
        proofPack: [row1, row2],
        actionSummary: 'unchanged until caller resynths',
      );
      final out = r.withProofPackClampedToUploadedSlots(const ['Document 1']);
      expect(out.proofPack[0].assessment, AssessmentLabel.likelySatisfies);
      expect(out.proofPack[1].isMissing, isTrue);
      expect(out.proofPack[1].evidence, '');
      expect(out.proofPack[1].caveats, contains('Prior note'));
      expect(out.proofPack[1].caveats, contains('Adjusted on-device'));
      expect(out.actionSummary, r.actionSummary);
    });

    test('withProofPackClamped is identity when no slot overflow', () {
      const ns = NoticeSummary(
        requestedCategories: <String>[],
        deadline: '',
        consequence: '',
      );
      final row = ProofPackItem(
        category: 'Income',
        matchedDocument: 'Pay stub',
        assessment: AssessmentLabel.likelySatisfies,
        confidence: ConfidenceLevel.high,
        evidence: 'Document 1 shows YTD',
        caveats: '',
      );
      final r = TrackAResult(
        noticeSummary: ns,
        proofPack: [row],
        actionSummary: 'x',
      );
      final out = r.withProofPackClampedToUploadedSlots(const ['Document 1']);
      expect(identical(r, out), isTrue);
    });
  });

  group('TrackAResult proof pack deduplication by category', () {
    const ns = NoticeSummary(
      requestedCategories: <String>[],
      deadline: '',
      consequence: '',
    );

    ProofPackItem earnedSatisfied() => const ProofPackItem(
          category: 'earned_income',
          matchedDocument: 'Document 1',
          assessment: AssessmentLabel.likelySatisfies,
          confidence: ConfidenceLevel.high,
          evidence: 'stub on doc 1',
          caveats: '',
        );

    ProofPackItem earnedSpuriousMissing() => const ProofPackItem(
          category: 'earned_income',
          matchedDocument: 'MISSING',
          assessment: AssessmentLabel.missing,
          confidence: ConfidenceLevel.low,
          evidence: '',
          caveats: '',
        );

    test('keeps one row per category, preferring likely_satisfies over missing', () {
      final r = TrackAResult(
        noticeSummary: ns,
        proofPack: [earnedSatisfied(), earnedSpuriousMissing()],
        actionSummary: '',
      );
      expect(r.proofPackDeduplicatedByCategory, hasLength(1));
      expect(
        r.proofPackDeduplicatedByCategory.first.assessment,
        AssessmentLabel.likelySatisfies,
      );
    });

    test('same when satisfied row comes after duplicate missing', () {
      final r = TrackAResult(
        noticeSummary: ns,
        proofPack: [earnedSpuriousMissing(), earnedSatisfied()],
        actionSummary: '',
      );
      expect(r.proofPackDeduplicatedByCategory, hasLength(1));
      expect(
        r.proofPackDeduplicatedByCategory.first.assessment,
        AssessmentLabel.likelySatisfies,
      );
    });

    test('synthesizeTrackAActionSummary does not list category as missing', () {
      final r = TrackAResult(
        noticeSummary: ns,
        proofPack: [earnedSatisfied(), earnedSpuriousMissing()],
        actionSummary: '',
      );
      final s = LabelFormatter.synthesizeTrackAActionSummary(r);
      expect(
        s,
        isNot(contains('Gather and submit the missing proof for:')),
      );
    });
  });
}

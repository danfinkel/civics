import 'package:civiclens/core/models/track_a_result.dart';
import 'package:civiclens/core/models/track_b_result.dart';
import 'package:civiclens/core/utils/label_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('trackBRequirementResidentTitle', () {
    test('shortens long BPS age line to resident title', () {
      final r = RequirementResult(
        requirement: 'child age proof (birth cert/passport)',
        status: RequirementStatus.questionable,
        matchedDocument: 'CERTIFICATE OF LIVE BIRTH',
        evidence: '',
        notes: '',
        confidence: ConfidenceLevel.medium,
      );
      expect(trackBRequirementResidentTitle(r), "Proof of child's age");
    });

    test('replaces prompt-leakage requirement with inferred title', () {
      final r = RequirementResult(
        requirement:
            'TWO docs same category = only one proof — set duplicate_category_flag true.',
        status: RequirementStatus.satisfied,
        matchedDocument: 'RESIDENTIAL LEASE AGREEMENT',
        evidence: '',
        notes: '',
        confidence: ConfidenceLevel.high,
      );
      expect(trackBRequirementResidentTitle(r), 'Boston residency proof');
    });

    test('infers age proof from matched document when requirement is OCR junk', () {
      final r = RequirementResult(
        requirement: 'OCR from 4 document(s) (may have errors)',
        status: RequirementStatus.satisfied,
        matchedDocument: 'CERTIFICATE OF LIVE BIRTH',
        evidence: '',
        notes: '',
        confidence: ConfidenceLevel.high,
      );
      expect(trackBRequirementResidentTitle(r), "Proof of child's age");
    });
  });

  group('displayFamilySummary', () {
    test('returns model text when non-empty', () {
      final r = TrackBResult(
        requirements: const [],
        duplicateCategoryFlag: false,
        duplicateCategoryExplanation: '',
        familySummary: '  Bring birth cert.  ',
      );
      expect(r.displayFamilySummary, 'Bring birth cert.');
    });

    test('synthesizes when family_summary is empty', () {
      final r = TrackBResult(
        requirements: [
          RequirementResult(
            requirement: 'proof_of_age',
            status: RequirementStatus.questionable,
            matchedDocument: 'Birth cert',
            evidence: '',
            notes: '',
            confidence: ConfidenceLevel.medium,
          ),
          RequirementResult(
            requirement: 'residency_proof_1',
            status: RequirementStatus.missing,
            matchedDocument: 'MISSING',
            evidence: '',
            notes: '',
            confidence: ConfidenceLevel.low,
          ),
        ],
        duplicateCategoryFlag: false,
        duplicateCategoryExplanation: '',
        familySummary: '',
      );
      final s = r.displayFamilySummary;
      expect(s, isNotEmpty);
      expect(s, contains('Bring these originals'));
      expect(s, contains('Ask BPS staff'));
      expect(s, contains('Proof of Age'));
      expect(s, contains('Not found'));
    });

    test('synthesized summary dedupes identical requirement titles', () {
      final longRes = 'TWO Boston residency proofs from different categories '
          '(lease/deed, utility, bank stmt, gov mail, employer letter, affidavit)';
      final r = TrackBResult(
        requirements: [
          RequirementResult(
            requirement: longRes,
            status: RequirementStatus.questionable,
            matchedDocument: 'LEASE A',
            evidence: '',
            notes: '',
            confidence: ConfidenceLevel.medium,
          ),
          RequirementResult(
            requirement: longRes,
            status: RequirementStatus.questionable,
            matchedDocument: 'LEASE B',
            evidence: '',
            notes: '',
            confidence: ConfidenceLevel.medium,
          ),
        ],
        duplicateCategoryFlag: false,
        duplicateCategoryExplanation: '',
        familySummary: '',
      );
      final s = r.displayFamilySummary;
      expect('Boston residency proof'.allMatches(s).length, 1);
    });
  });

  group('trackBQuestionableResidentExplanation', () {
    test('uses evidence when present', () {
      final r = RequirementResult(
        requirement: 'x',
        status: RequirementStatus.questionable,
        matchedDocument: 'Phone bill',
        evidence: 'Cell phone bills are sometimes rejected for residency.',
        notes: '',
        confidence: ConfidenceLevel.medium,
      );
      expect(
        trackBQuestionableResidentExplanation(r),
        contains('Cell phone'),
      );
    });

    test('returns default when evidence is too short', () {
      final r = RequirementResult(
        requirement: 'x',
        status: RequirementStatus.questionable,
        matchedDocument: 'x',
        evidence: 'short',
        notes: '',
        confidence: ConfidenceLevel.medium,
      );
      expect(
        trackBQuestionableResidentExplanation(r),
        contains('green check'),
      );
    });

    test('ignores OCR garbage evidence', () {
      final garbage =
          'CERTIFICATE OF LIVE BIRTH vHa koceris ${'x' * 200} CHLDS LEBAL';
      final r = RequirementResult(
        requirement: 'proof_of_age',
        status: RequirementStatus.questionable,
        matchedDocument: 'X',
        evidence: garbage,
        notes: '',
        confidence: ConfidenceLevel.medium,
      );
      expect(
        trackBQuestionableResidentExplanation(r),
        contains('green check'),
      );
    });
  });

  group('trackBMatchedDocumentSubtitle', () {
    test('replaces long OCR blob with kind + note', () {
      final long =
          'RESIDENTIAL LEASE AGREEMENT ${'Z' * 150} RESIDENTIAL LEASE AGREEMENT';
      final r = RequirementResult(
        requirement: 'residency_proof_1',
        status: RequirementStatus.questionable,
        matchedDocument: long,
        evidence: '',
        notes: '',
        confidence: ConfidenceLevel.medium,
      );
      final s = trackBMatchedDocumentSubtitle(r);
      expect(s, contains('Lease'));
      expect(s, contains('messy'));
      expect(s, isNot(contains('ZZZZ')));
    });
  });

  group('TrackBResult.alignToUploadSlots', () {
    const slots = [
      'Proof of Age: Birth certificate or passport',
      'Residency Proof 1: Lease, deed, or utility bill',
      'Residency Proof 2: From a different category than Proof 1',
      'Immunization Record: Current vaccination record',
    ];

    test('drops extra model rows; one output row per upload slot', () {
      final parsed = TrackBResult(
        requirements: [
          RequirementResult(
            requirement: 'lease',
            status: RequirementStatus.questionable,
            matchedDocument: 'LEASE A',
            evidence: '',
            notes: '',
            confidence: ConfidenceLevel.medium,
          ),
          RequirementResult(
            requirement: 'lease',
            status: RequirementStatus.questionable,
            matchedDocument: 'LEASE B',
            evidence: '',
            notes: '',
            confidence: ConfidenceLevel.medium,
          ),
          RequirementResult(
            requirement: 'proof_of_age',
            status: RequirementStatus.questionable,
            matchedDocument: 'BIRTH',
            evidence: '',
            notes: '',
            confidence: ConfidenceLevel.medium,
          ),
          RequirementResult(
            requirement: 'junk',
            status: RequirementStatus.satisfied,
            matchedDocument: 'OCR noise',
            evidence: '',
            notes: '',
            confidence: ConfidenceLevel.high,
          ),
          RequirementResult(
            requirement: 'immunization_record',
            status: RequirementStatus.satisfied,
            matchedDocument: 'VACCINE CARD',
            evidence: '',
            notes: '',
            confidence: ConfidenceLevel.high,
          ),
        ],
        duplicateCategoryFlag: false,
        duplicateCategoryExplanation: '',
        familySummary: '',
      );

      final aligned = TrackBResult.alignToUploadSlots(
        parsed,
        slotDescriptions: slots,
      );

      expect(aligned.requirements.length, slots.length);
      expect(aligned.requirements[0].requirement, 'proof_of_age');
      expect(aligned.requirements[1].matchedDocument, 'LEASE A');
      expect(aligned.requirements[2].matchedDocument, 'LEASE B');
      expect(aligned.requirements[3].requirement, 'immunization_record');
      expect(aligned.requirements[3].matchedDocument, 'VACCINE CARD');
    });

    test(
      'strips prompt-echo requirement rows so imm slot is not a bogus lease row',
      () {
        const badLeaseEvidence =
            'RESIDENTIAL LEASE\nnotererishot me b\nSYNHETIG cocMNTHOTCert';
        final parsed = TrackBResult(
          requirements: [
            RequirementResult(
              requirement: 'child age proof (birth cert/passport)',
              status: RequirementStatus.questionable,
              matchedDocument: 'CERTIFICATE OF LIVE BIRTH',
              evidence: 'noisy ocr',
              notes: 'illegible',
              confidence: ConfidenceLevel.uncertain,
            ),
            RequirementResult(
              requirement: 'residency_proof_1',
              status: RequirementStatus.questionable,
              matchedDocument: 'LEASE A',
              evidence: '',
              notes: '',
              confidence: ConfidenceLevel.uncertain,
            ),
            RequirementResult(
              requirement: 'residency_proof_2',
              status: RequirementStatus.questionable,
              matchedDocument: 'LEASE B',
              evidence: badLeaseEvidence,
              notes: '',
              confidence: ConfidenceLevel.uncertain,
            ),
            RequirementResult(
              requirement:
                  'TWO docs same category = only one proof — set duplicate_category_flag true.',
              status: RequirementStatus.satisfied,
              matchedDocument: 'RESIDENTIAL LEASE AGREEMENT',
              evidence: badLeaseEvidence,
              notes: 'Echo of instructions, not a document type.',
              confidence: ConfidenceLevel.uncertain,
            ),
            RequirementResult(
              requirement: 'OCR from 4 document(s) (may have errors)',
              status: RequirementStatus.satisfied,
              matchedDocument: 'CERTIFICATE OF LIVE BIRTH',
              evidence: '',
              notes: '',
              confidence: ConfidenceLevel.uncertain,
            ),
          ],
          duplicateCategoryFlag: false,
          duplicateCategoryExplanation: '',
          familySummary: '',
        );

        final aligned = TrackBResult.alignToUploadSlots(
          parsed,
          slotDescriptions: slots,
        );

        expect(aligned.requirements.length, 4);
        expect(aligned.requirements[3].requirement, 'immunization_record');
        expect(aligned.requirements[3].status, RequirementStatus.missing);
        expect(aligned.requirements[3].matchedDocument, 'MISSING');
      },
    );

    test(
      'when row count matches slots, trusts document order and rekeys wrong slug',
      () {
        final parsed = TrackBResult(
          requirements: [
            RequirementResult(
              requirement: 'proof_of_age',
              status: RequirementStatus.questionable,
              matchedDocument: 'BIRTH',
              evidence: '',
              notes: '',
              confidence: ConfidenceLevel.medium,
            ),
            RequirementResult(
              requirement: 'residency_proof_1',
              status: RequirementStatus.questionable,
              matchedDocument: 'LEASE A',
              evidence: '',
              notes: '',
              confidence: ConfidenceLevel.medium,
            ),
            RequirementResult(
              requirement: 'residency_proof_2',
              status: RequirementStatus.questionable,
              matchedDocument: 'LEASE B',
              evidence: '',
              notes: '',
              confidence: ConfidenceLevel.medium,
            ),
            RequirementResult(
              requirement: 'residency_proof_1',
              status: RequirementStatus.questionable,
              matchedDocument: 'TDAP / school immunization form',
              evidence: 'Boston address on header',
              notes: '',
              confidence: ConfidenceLevel.medium,
            ),
          ],
          duplicateCategoryFlag: false,
          duplicateCategoryExplanation: '',
          familySummary: '',
        );

        final aligned = TrackBResult.alignToUploadSlots(
          parsed,
          slotDescriptions: slots,
        );

        expect(aligned.requirements.length, 4);
        expect(aligned.requirements[3].requirement, 'immunization_record');
        expect(
          aligned.requirements[3].matchedDocument,
          'TDAP / school immunization form',
        );
        expect(
          trackBRequirementResidentTitle(aligned.requirements[3]),
          'Immunization Record',
        );
      },
    );

    test('injects missing immunization when model omits it', () {
      final parsed = TrackBResult(
        requirements: [
          RequirementResult(
            requirement: 'proof_of_age',
            status: RequirementStatus.questionable,
            matchedDocument: 'BIRTH',
            evidence: '',
            notes: '',
            confidence: ConfidenceLevel.medium,
          ),
          RequirementResult(
            requirement: 'residency_proof_1',
            status: RequirementStatus.questionable,
            matchedDocument: 'L1',
            evidence: '',
            notes: '',
            confidence: ConfidenceLevel.medium,
          ),
          RequirementResult(
            requirement: 'residency_proof_2',
            status: RequirementStatus.questionable,
            matchedDocument: 'L2',
            evidence: '',
            notes: '',
            confidence: ConfidenceLevel.medium,
          ),
        ],
        duplicateCategoryFlag: false,
        duplicateCategoryExplanation: '',
        familySummary: '',
      );

      final aligned = TrackBResult.alignToUploadSlots(
        parsed,
        slotDescriptions: slots,
      );

      expect(aligned.requirements.length, 4);
      expect(aligned.requirements[3].requirement, 'immunization_record');
      expect(aligned.requirements[3].status, RequirementStatus.missing);
      expect(aligned.requirements[3].matchedDocument, 'MISSING');
    });
  });

  group('requirementsForDisplay', () {
    test('keeps satisfied rows when another row is questionable', () {
      final r = TrackBResult(
        requirements: [
          RequirementResult(
            requirement: 'proof_of_age',
            status: RequirementStatus.questionable,
            matchedDocument: 'X',
            evidence: '',
            notes: '',
            confidence: ConfidenceLevel.medium,
          ),
          RequirementResult(
            requirement: 'residency_proof_1',
            status: RequirementStatus.satisfied,
            matchedDocument: 'Lease',
            evidence: '',
            notes: '',
            confidence: ConfidenceLevel.high,
          ),
        ],
        duplicateCategoryFlag: false,
        duplicateCategoryExplanation: '',
        familySummary: '',
      );
      expect(r.satisfiedCountRaw, 1);
      expect(r.satisfiedCount, 1);
      expect(r.requirementsForDisplay[0].status, RequirementStatus.questionable);
      expect(r.requirementsForDisplay[1].status, RequirementStatus.satisfied);
    });

    test('leaves satisfied when nothing is questionable', () {
      final r = TrackBResult(
        requirements: [
          RequirementResult(
            requirement: 'proof_of_age',
            status: RequirementStatus.satisfied,
            matchedDocument: 'Birth',
            evidence: '',
            notes: '',
            confidence: ConfidenceLevel.high,
          ),
          RequirementResult(
            requirement: 'residency_proof_1',
            status: RequirementStatus.missing,
            matchedDocument: 'MISSING',
            evidence: '',
            notes: '',
            confidence: ConfidenceLevel.low,
          ),
        ],
        duplicateCategoryFlag: false,
        duplicateCategoryExplanation: '',
        familySummary: '',
      );
      expect(r.satisfiedCount, 1);
      expect(r.requirementsForDisplay[0].status, RequirementStatus.satisfied);
    });
  });

  group('trackBNextStepsLead', () {
    test('mentions staff for questionable rows', () {
      final r = TrackBResult(
        requirements: [
          RequirementResult(
            requirement: 'proof_of_age',
            status: RequirementStatus.questionable,
            matchedDocument: 'X',
            evidence: '',
            notes: '',
            confidence: ConfidenceLevel.medium,
          ),
        ],
        duplicateCategoryFlag: false,
        duplicateCategoryExplanation: '',
        familySummary: '',
      );
      expect(trackBNextStepsLead(r), contains('BPS'));
      expect(trackBNextStepsLead(r), contains('originals'));
    });
  });

  group('TrackBResult.withResidencyProof2QuestionableWhenDuplicateCategory', () {
    RequirementResult row(
      String requirement,
      RequirementStatus status,
    ) {
      return RequirementResult(
        requirement: requirement,
        status: status,
        matchedDocument: 'RESIDENTIAL LEASE',
        evidence: '',
        notes: '',
        confidence: ConfidenceLevel.high,
      );
    }

    test('demotes satisfied residency_proof_2 when duplicate flag is set', () {
      final base = TrackBResult(
        requirements: [
          row('proof_of_age', RequirementStatus.satisfied),
          row('residency_proof_1', RequirementStatus.satisfied),
          row('residency_proof_2', RequirementStatus.satisfied),
          row('immunization_record', RequirementStatus.missing),
        ],
        duplicateCategoryFlag: true,
        duplicateCategoryExplanation: 'Both uploads are leases.',
        familySummary: '',
      );
      final out = base.withResidencyProof2QuestionableWhenDuplicateCategory();
      expect(out.requirements[2].status, RequirementStatus.questionable);
      expect(
        out.requirements[2].evidence,
        contains('BPS counts two documents'),
      );
      expect(out.requirements[0].status, RequirementStatus.satisfied);
    });

    test('is identity when duplicate flag is false', () {
      final base = TrackBResult(
        requirements: [
          row('residency_proof_2', RequirementStatus.satisfied),
        ],
        duplicateCategoryFlag: false,
        duplicateCategoryExplanation: '',
        familySummary: '',
      );
      expect(
        identical(base, base.withResidencyProof2QuestionableWhenDuplicateCategory()),
        isTrue,
      );
    });

    test(
      'infers duplicate when model omits flag but both residency rows are lease-like',
      () {
      final base = TrackBResult(
        requirements: [
          row('proof_of_age', RequirementStatus.satisfied),
          RequirementResult(
            requirement: 'residency_proof_1',
            status: RequirementStatus.satisfied,
            matchedDocument: 'RESIDENTIAL LEASE AGREEMENT',
            evidence: 'Unit 4B',
            notes: '',
            confidence: ConfidenceLevel.high,
          ),
          RequirementResult(
            requirement: 'residency_proof_2',
            status: RequirementStatus.satisfied,
            matchedDocument: 'LEASE RIDER',
            evidence: 'Addendum to tenancy',
            notes: '',
            confidence: ConfidenceLevel.high,
          ),
          row('immunization_record', RequirementStatus.satisfied),
        ],
        duplicateCategoryFlag: false,
        duplicateCategoryExplanation: '',
        familySummary: '',
      );
      final out = base.withResidencyProof2QuestionableWhenDuplicateCategory();
      expect(out.requirements[2].status, RequirementStatus.questionable);
      expect(out.duplicateCategoryFlag, isTrue);
      expect(out.duplicateCategoryExplanation, contains('lease'));
    });

    test(
      'infers duplicate when matched is lease but evidence claims another category',
      () {
      final base = TrackBResult(
        requirements: [
          row('proof_of_age', RequirementStatus.satisfied),
          RequirementResult(
            requirement: 'residency_proof_1',
            status: RequirementStatus.satisfied,
            matchedDocument: 'RESIDENTIAL LEASE AGREEMENT',
            evidence: 'Shows landlord and unit.',
            notes: '',
            confidence: ConfidenceLevel.high,
          ),
          RequirementResult(
            requirement: 'residency_proof_2',
            status: RequirementStatus.satisfied,
            matchedDocument: 'RESIDENTIAL LEASE ADDENDUM',
            evidence:
                'This document is a utility bill, a different category than Proof 1.',
            notes: '',
            confidence: ConfidenceLevel.high,
          ),
          row('immunization_record', RequirementStatus.satisfied),
        ],
        duplicateCategoryFlag: false,
        duplicateCategoryExplanation: '',
        familySummary: '',
      );
      final out = base.withResidencyProof2QuestionableWhenDuplicateCategory();
      expect(out.requirements[2].status, RequirementStatus.questionable);
      expect(out.duplicateCategoryFlag, isTrue);
    });

    test('does not infer duplicate when second proof is a utility bill', () {
      final base = TrackBResult(
        requirements: [
          row('proof_of_age', RequirementStatus.satisfied),
          RequirementResult(
            requirement: 'residency_proof_1',
            status: RequirementStatus.satisfied,
            matchedDocument: 'RESIDENTIAL LEASE',
            evidence: '',
            notes: '',
            confidence: ConfidenceLevel.high,
          ),
          RequirementResult(
            requirement: 'residency_proof_2',
            status: RequirementStatus.satisfied,
            matchedDocument: 'EVERSOURCE',
            evidence: 'electric utility bill',
            notes: '',
            confidence: ConfidenceLevel.high,
          ),
          row('immunization_record', RequirementStatus.satisfied),
        ],
        duplicateCategoryFlag: false,
        duplicateCategoryExplanation: '',
        familySummary: '',
      );
      final out = base.withResidencyProof2QuestionableWhenDuplicateCategory();
      expect(out.requirements[2].status, RequirementStatus.satisfied);
      expect(out.duplicateCategoryFlag, isFalse);
    });
  });

  group('LabelFormatter.duplicateCategoryUserMessage', () {
    test('appends acceptable second-proof examples when not already present', () {
      final msg = LabelFormatter.duplicateCategoryUserMessage(
        'The two residency proofs are both lease agreements.',
      );
      expect(msg, contains('lease'));
      expect(msg.toLowerCase(), contains('utility bill'));
    });
  });
}

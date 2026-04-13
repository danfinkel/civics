import 'package:flutter_test/flutter_test.dart';
import 'package:civiclens/core/inference/response_parser.dart';
import 'package:civiclens/core/models/track_b_result.dart';
import 'package:civiclens/core/models/track_a_result.dart';

void main() {
  group('ResponseParser', () {
    test('should parse valid Track B JSON', () {
      const json = '''
{
  "requirements": [
    {
      "requirement": "Proof of Age",
      "status": "satisfied",
      "matched_document": "Document 1: birth certificate",
      "evidence": "Shows child's date of birth",
      "notes": "",
      "confidence": "high"
    }
  ],
  "duplicate_category_flag": false,
  "duplicate_category_explanation": "",
  "family_summary": "Your packet is complete."
}
''';

      final result = ResponseParser.parseTrackB(json);
      expect(result.isSuccess, true);
      expect(result.data, isNotNull);
      expect(result.data!.requirements.length, 1);
      expect(result.data!.requirements[0].requirement, 'Proof of Age');
      expect(result.data!.requirements[0].status, RequirementStatus.satisfied);
      expect(result.data!.duplicateCategoryFlag, false);
    });

    test('should parse Track B JSON without outer braces', () {
      // Simulates the E4B output that occasionally omits braces
      const json = '''
"requirements": [
  {
    "requirement": "Proof of Age",
    "status": "satisfied",
    "matched_document": "Document 1",
    "evidence": "Shows DOB",
    "notes": "",
    "confidence": "high"
  }
],
"duplicate_category_flag": false,
"duplicate_category_explanation": "",
"family_summary": "Complete."
''';

      final result = ResponseParser.parseTrackB(json);
      expect(result.isSuccess, true);
      expect(result.data, isNotNull);
      expect(result.data!.requirements.length, 1);
    });

    test('should parse JSON with markdown fences', () {
      const json = '''```json
{
  "requirements": [],
  "duplicate_category_flag": false,
  "duplicate_category_explanation": "",
  "family_summary": "Test"
}
```''';

      final result = ResponseParser.parseTrackB(json);
      expect(result.isSuccess, true);
      expect(result.data, isNotNull);
      expect(result.data!.familySummary, 'Test');
    });

    test('should return failure for invalid JSON', () {
      const json = 'not valid json at all';
      final result = ResponseParser.parseTrackB(json);
      expect(result.isSuccess, false);
      expect(result.data, isNull);
    });

    test('should parse JSON when evidence contains } character', () {
      const json = r'''
{
  "requirements": [
    {
      "requirement": "Proof of Age",
      "status": "satisfied",
      "matched_document": "Birth cert",
      "evidence": "Closing brace in OCR: } still inside string",
      "notes": "",
      "confidence": "high"
    }
  ],
  "duplicate_category_flag": false,
  "duplicate_category_explanation": "",
  "family_summary": "OK"
}
''';
      final result = ResponseParser.parseTrackB(json);
      expect(result.isSuccess, true);
      expect(result.data!.requirements.first.evidence, contains('}'));
    });

    test('should parse JSON with trailing commas', () {
      const json = '''
{
  "requirements": [],
  "duplicate_category_flag": false,
  "duplicate_category_explanation": "",
  "family_summary": "Test",
}
''';
      final result = ResponseParser.parseTrackB(json);
      expect(result.isSuccess, true);
      expect(result.data!.familySummary, 'Test');
    });

    test('should wrap root-level requirements array', () {
      const json = '''
[
  {
    "requirement": "Proof of Age",
    "status": "satisfied",
    "matched_document": "Doc 1",
    "evidence": "ok"
  }
]
''';
      final result = ResponseParser.parseTrackB(json);
      expect(result.isSuccess, true);
      expect(result.data!.requirements.length, 1);
      expect(result.data!.familySummary, '');
    });

    test('should parse valid Track A JSON', () {
      const json = '''
{
  "notice_summary": {
    "requested_categories": ["Income Proof"],
    "deadline": "April 15, 2026",
    "consequence": "Benefits may be discontinued"
  },
  "proof_pack": [
    {
      "category": "Income Proof",
      "matched_document": "Document 1: pay stub",
      "assessment": "likely_satisfies",
      "confidence": "high",
      "evidence": "Shows employer and pay",
      "caveats": ""
    }
  ],
  "action_summary": "Submit by April 15."
}
''';

      final result = ResponseParser.parseTrackA(json);
      expect(result.isSuccess, true);
      expect(result.data, isNotNull);
      expect(result.data!.noticeSummary.deadline, 'April 15, 2026');
      expect(result.data!.proofPack.length, 1);
      expect(result.data!.proofPack[0].assessment, AssessmentLabel.likelySatisfies);
    });

    test('Track A: recovers when JSON is truncated mid-stream', () {
      const raw = '''
Here is the result:
{"notice_summary":{"requested_categories":["earned_income"],"deadline":"May 1","consequence":"x"},"proof_pack":[{"category":"earned_income","matched_document":"D1","assessment":"likely_satisfies","confidence":"high","evidence":"pay period visible","caveats":""},{"category":"rent","matched_document":"MISSING","assessment":"missing","confidence":"low","evidence":"","caveats":""}],"action_summary":"Please submit''';

      final result = ResponseParser.parseTrackA(raw);
      expect(result.isSuccess, true, reason: result.errorMessage);
      expect(result.data!.proofPack.length, greaterThanOrEqualTo(1));
    });

    test('Track A: ignores prose after closing brace', () {
      const raw = r'''
{"notice_summary":{"requested_categories":[],"deadline":"Jan 1","consequence":""},"proof_pack":[],"action_summary":"Done"}
Hope this helps!
''';

      final result = ResponseParser.parseTrackA(raw);
      expect(result.isSuccess, true);
      expect(result.data!.actionSummary, 'Done');
    });

    test('Track A: raw newlines inside JSON string values', () {
      const raw = r'''
{"notice_summary":{"requested_categories":["x"],"deadline":"d","consequence":"c"},"proof_pack":[{"category":"k","matched_document":"D1","assessment":"likely_satisfies","confidence":"high","evidence":"Line one
Line two","caveats":""}],"action_summary":"Go"}
''';

      final result = ResponseParser.parseTrackA(raw);
      expect(result.isSuccess, true, reason: result.errorMessage);
      expect(result.data!.proofPack.first.evidence, contains('Line one'));
    });

    test('Track A: unclosed markdown json fence still parses', () {
      const raw = '''```json
{"notice_summary":{"requested_categories":[],"deadline":"1/1","consequence":""},"proof_pack":[],"action_summary":"x"}''';

      final result = ResponseParser.parseTrackA(raw);
      expect(result.isSuccess, true, reason: result.errorMessage);
    });

    test('Track A: preamble before JSON object', () {
      const raw = '''
Sure! Here you go:
{"notice_summary":{"requested_categories":[],"deadline":"Feb 2","consequence":""},"proof_pack":[],"action_summary":"y"}
''';

      final result = ResponseParser.parseTrackA(raw);
      expect(result.isSuccess, true, reason: result.errorMessage);
      expect(result.data!.noticeSummary.deadline, 'Feb 2');
    });

    test(
      'Track A: repairs Gemma ""deadline" and trailing action_summary: prose (device)',
      () {
        const raw = r'''
{"notice_summary":{"requested_categories":["Income"],""deadline":"April 15, 2026","consequence":"Case closed."},"proof_pack":[{"category":"Income","matched_document":"Document 1","assessment":"likely_satisfies","confidence":"high","evidence":"e1"},{"category":"Income","matched_document":"Document 2","assessment":"likely_satisfies","confidence":"medium","evidence":"e2"}]}
action_summary:Next steps for the resident here.
''';

        final result = ResponseParser.parseTrackA(raw);
        expect(result.isSuccess, true, reason: result.errorMessage);
        expect(result.data!.noticeSummary.deadline, 'April 15, 2026');
        expect(result.data!.noticeSummary.requestedCategories, contains('Income'));
        expect(result.data!.proofPack.length, 2);
        expect(result.data!.actionSummary, contains('Next steps'));
      },
    );

    test(
      'Track A: repairs Gemma stray .","} before proof_pack close (device log case)',
      () {
        const raw =
            '{"notice_summary":{"requested_categories":["Income"],"deadline":"[Not specified","consequence":"[Not specified]"},"proof_pack":[{"category":"Income","matched_document":"Document 1","assessment":"likely_satisfies","confidence":"high","evidence":"Document 1 contains an earnings statement showing gross pay and deductions for a recent pay period.","caveats":"The notice requests verification of earned income.","}],"action_summary":"Next steps."}';

        final result = ResponseParser.parseTrackA(raw);
        expect(result.isSuccess, true, reason: result.errorMessage);
        expect(result.data!.proofPack.length, 1);
        expect(result.data!.proofPack.first.matchedDocument, 'Document 1');
        expect(result.data!.noticeSummary.requestedCategories, contains('Income'));
        expect(result.data!.noticeSummary.isUncertain, true);
      },
    );

    test('parseTrackANoticePreview: valid flat JSON', () {
      const json = '''
{"requested_categories":["earned_income","residency"],"deadline":"April 1","hint":"Upload pay stubs."}
''';

      final result = ResponseParser.parseTrackANoticePreview(json);
      expect(result.isSuccess, true, reason: result.errorMessage);
      expect(result.data!.requestedCategories.length, 2);
      expect(result.data!.deadline, 'April 1');
      expect(result.data!.hint, 'Upload pay stubs.');
    });

    test('parseTrackANoticePreview: markdown fence', () {
      const json = '''```json
{"requested_categories":[],"deadline":"","hint":""}
```''';

      final result = ResponseParser.parseTrackANoticePreview(json);
      expect(result.isSuccess, true, reason: result.errorMessage);
      expect(result.data!.hasAnySignal, false);
    });
  });
}

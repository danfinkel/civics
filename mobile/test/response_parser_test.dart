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
  });
}

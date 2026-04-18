import 'package:civiclens/core/models/track_a_result.dart';
import 'package:civiclens/core/models/track_b_result.dart';
import 'package:civiclens/core/utils/label_formatter.dart';
import 'package:civiclens/features/track_b/widgets/duplicate_category_banner.dart';
import 'package:civiclens/features/track_b/widgets/requirement_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Track B duplicate category shows warning banner', (tester) async {
    const explanation = 'same_residency_category_duplicate';
    final friendly = LabelFormatter.duplicateCategoryUserMessage(explanation);
    final text = friendly.isNotEmpty
        ? friendly
        : 'Two leases count as one proof — you need a second document type from a different category';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: TrackBDuplicateCategoryBanner(message: text),
          ),
        ),
      ),
    );

    expect(find.textContaining('Two leases'), findsOneWidget);
    expect(find.textContaining('different'), findsOneWidget);
    expect(find.textContaining('utility bill'), findsOneWidget);
  });

  testWidgets(
    'RequirementRow: questionable badge wraps without collapsing title',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 280,
                child: RequirementRow(
                  requirement: RequirementResult(
                    requirement: 'Proof of Age',
                    status: RequirementStatus.questionable,
                    matchedDocument: 'Document 1',
                    evidence: '',
                    notes: '',
                    confidence: ConfidenceLevel.medium,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Proof of Age'), findsOneWidget);
      expect(
        find.textContaining('Accepted by some offices'),
        findsOneWidget,
      );
    },
  );
}

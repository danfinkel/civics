import 'package:civiclens/core/models/track_a_result.dart';
import 'package:civiclens/features/track_a/widgets/track_a_results_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Track A results shows deadline prominently', (tester) async {
    final mockResult = TrackAResult(
      noticeSummary: const NoticeSummary(
        requestedCategories: ['earned_income'],
        deadline: 'April 15, 2026',
        consequence: 'case_closure',
      ),
      proofPack: const [
        ProofPackItem(
          category: 'earned_income',
          matchedDocument: 'D03',
          assessment: AssessmentLabel.likelySatisfies,
          confidence: ConfidenceLevel.high,
          evidence: '',
          caveats: '',
        ),
      ],
      actionSummary: 'Your pay stub appears to cover what DTA is asking for.',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 900,
          child: TrackAResultsScreen(result: mockResult),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('April 15, 2026'), findsOneWidget);
    expect(find.textContaining('Respond by'), findsOneWidget);
    expect(
      find.textContaining('The notice asks you to send proof for:'),
      findsOneWidget,
    );

    expect(find.text('likely_satisfies'), findsNothing);
    expect(find.text('high'), findsNothing);
    expect(find.textContaining('High confidence'), findsOneWidget);

    expect(
      find.textContaining('pay stub appears to cover'),
      findsOneWidget,
    );
  });

  testWidgets('Track A results shows MISSING item with resident-friendly label',
      (tester) async {
    final mockResult = TrackAResult(
      noticeSummary: const NoticeSummary(
        requestedCategories: ['earned_income'],
        deadline: 'April 15, 2026',
        consequence: 'case_closure',
      ),
      proofPack: const [
        ProofPackItem(
          category: 'earned_income',
          matchedDocument: 'MISSING',
          assessment: AssessmentLabel.missing,
          confidence: ConfidenceLevel.low,
          evidence: '',
          caveats: '',
        ),
      ],
      actionSummary: "You're missing 1 required document.",
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 900,
          child: TrackAResultsScreen(result: mockResult),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Not found in your documents'), findsOneWidget);
    expect(find.text('MISSING'), findsNothing);
  });
}

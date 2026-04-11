import 'package:civiclens/core/utils/label_formatter.dart';
import 'package:civiclens/features/track_b/widgets/duplicate_category_banner.dart';
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
  });
}

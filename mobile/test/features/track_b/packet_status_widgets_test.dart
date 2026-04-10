import 'package:civiclens/core/models/track_a_result.dart';
import 'package:civiclens/core/models/track_b_result.dart';
import 'package:civiclens/features/track_b/widgets/packet_status_hero.dart';
import 'package:civiclens/features/track_b/widgets/packet_status_stat_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

RequirementResult _req(
  RequirementStatus status, {
  ConfidenceLevel confidence = ConfidenceLevel.high,
}) {
  return RequirementResult(
    requirement: 'Proof of Age',
    status: status,
    matchedDocument: status == RequirementStatus.missing ? 'MISSING' : 'Birth certificate',
    evidence: '',
    notes: '',
    confidence: confidence,
  );
}

TrackBResult _result(List<RequirementResult> requirements) {
  return TrackBResult(
    requirements: requirements,
    duplicateCategoryFlag: false,
    duplicateCategoryExplanation: '',
    familySummary: 'Bring originals to registration.',
  );
}

void main() {
  group('PacketStatusHero', () {
    testWidgets('shows APPLICATION VERIFIED only when all requirements satisfied',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PacketStatusHero(
                result: _result([
                  _req(RequirementStatus.satisfied),
                  _req(RequirementStatus.satisfied),
                ]),
              ),
            ),
          ),
        ),
      );

      expect(find.text('APPLICATION VERIFIED'), findsOneWidget);
      expect(find.text('REVIEW NEEDED'), findsNothing);
      expect(find.text('BPS Registration Center'), findsOneWidget);
    });

    testWidgets('shows REVIEW NEEDED when any requirement is not satisfied',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PacketStatusHero(
              result: _result([
                _req(RequirementStatus.satisfied),
                _req(RequirementStatus.missing),
              ]),
            ),
          ),
        ),
      );

      expect(find.text('REVIEW NEEDED'), findsOneWidget);
      expect(find.text('APPLICATION VERIFIED'), findsNothing);
    });

    testWidgets('shows PACKET STATUS when there are zero requirements',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PacketStatusHero(result: _result([])),
          ),
        ),
      );

      expect(find.text('PACKET STATUS'), findsOneWidget);
      expect(find.text('APPLICATION VERIFIED'), findsNothing);
      expect(find.text('REVIEW NEEDED'), findsNothing);
    });
  });

  group('PacketStatusStatCards', () {
    testWidgets('shows compliance headline from overall confidence', (tester) async {
      final low = _result([
        _req(RequirementStatus.satisfied, confidence: ConfidenceLevel.high),
        _req(RequirementStatus.missing, confidence: ConfidenceLevel.low),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PacketStatusStatCards(
                result: low,
                completedAt: DateTime(2026, 4, 9, 14, 30),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Needs verification'), findsOneWidget);
      expect(find.text('1 of 2 requirements satisfied'), findsOneWidget);
      expect(find.textContaining('2:30 PM'), findsOneWidget);
    });

    testWidgets('shows em dash when completedAt is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PacketStatusStatCards(
              result: _result([_req(RequirementStatus.satisfied)]),
              completedAt: null,
            ),
          ),
        ),
      );

      expect(find.text('—'), findsOneWidget);
    });
  });
}

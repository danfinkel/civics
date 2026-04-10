import 'package:flutter_test/flutter_test.dart';
import 'package:civiclens/main.dart';

void main() {
  testWidgets('app shows splash with CivicLens branding', (tester) async {
    await tester.pumpWidget(const CivicLensApp());
    await tester.pump();
    expect(find.text('CivicLens'), findsWidgets);
  });
}

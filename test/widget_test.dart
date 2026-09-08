import 'package:flutter_test/flutter_test.dart';
import 'package:metriscan/app.dart';

void main() {
  testWidgets('MetriScan app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MetriScanApp());
    expect(find.byType(MetriScanApp), findsOneWidget);
  });
}

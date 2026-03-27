import 'package:flutter_test/flutter_test.dart';

import 'package:relais/app.dart';

void main() {
  testWidgets('App renders ConnectScreen', (WidgetTester tester) async {
    await tester.pumpWidget(const RelaisApp());
    expect(find.text('Relais'), findsOneWidget);
    expect(find.text('Connect to a server'), findsOneWidget);
  });
}

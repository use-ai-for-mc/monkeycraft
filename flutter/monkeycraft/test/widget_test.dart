// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:monkeycraft_client/main.dart';

void main() {
  testWidgets('Shows login form', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('MonkeyCraft'), findsOneWidget);
    expect(find.text('Server address'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Remember password on this phone'), findsOneWidget);
  });

  testWidgets('Funnel host shows a password field', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Server address'),
      'something.ts.net',
    );
    await tester.pump();

    expect(find.text('Password'), findsOneWidget);
    expect(find.byTooltip('Show password'), findsOneWidget);
    expect(find.byTooltip('Copy password'), findsOneWidget);
  });
}

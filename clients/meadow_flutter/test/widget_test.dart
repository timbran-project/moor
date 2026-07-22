// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:meadow_flutter/main.dart';
import 'package:meadow_flutter/moor/args.dart';

void main() {
  testWidgets('Renders Login Screen', (WidgetTester tester) async {
    await tester.pumpWidget(MeadowApp(launchArgs: parseLaunchArgs(const [])));
    expect(find.text('mooR'), findsOneWidget);
    expect(find.text('Sign In'), findsWidgets);
    expect(find.text('Create Account'), findsOneWidget);
  });
}

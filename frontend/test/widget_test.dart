import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volt_guard/main.dart';

void main() {
  testWidgets('App displays welcome message', (WidgetTester tester) async {
    // Build the app and trigger a frame
    await tester.pumpWidget(const VoltGuardApp());

    // Verify that the welcome message is displayed
    expect(find.text('Welcome to Volt Guard'), findsOneWidget);
    expect(find.text('Smart Energy Management System'), findsOneWidget);
    expect(find.byIcon(Icons.energy_savings_leaf), findsOneWidget);
  });

  testWidgets('App has correct app bar title', (WidgetTester tester) async {
    // Build the app and trigger a frame
    await tester.pumpWidget(const VoltGuardApp());

    // Verify that the app bar title is correct
    expect(find.text('Volt Guard - Energy Management'), findsOneWidget);
  });
}

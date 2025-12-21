import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volt_guard/main.dart';

void main() {
  testWidgets('Shows splash then dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(const VoltGuardApp());

    expect(find.text('Volt Guard'), findsOneWidget);
    expect(find.text('Loading your energy cockpit...'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2000));
    expect(find.text('Smart energy,\nready for you.'), findsOneWidget);
  });

  testWidgets('Bottom bar includes required destinations', (WidgetTester tester) async {
    await tester.pumpWidget(const VoltGuardApp());
    await tester.pump(const Duration(milliseconds: 2000));

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Analytics'), findsOneWidget);
    expect(find.text('Alerts'), findsOneWidget);
    expect(find.text('Devices'), findsOneWidget);
    expect(find.text('Insights'), findsOneWidget);
  });

  testWidgets('Navigates to analytics tab', (WidgetTester tester) async {
    await tester.pumpWidget(const VoltGuardApp());
    await tester.pump(const Duration(milliseconds: 2000));

    await tester.tap(find.text('Analytics'));
    await tester.pumpAndSettle();

    expect(find.text('Usage this week'), findsOneWidget);
    expect(find.text('Predicted monthly spend'), findsOneWidget);
  });
}

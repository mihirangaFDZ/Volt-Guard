import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volt_guard/main.dart';

void main() {
  testWidgets('Landing page displays hero section', (WidgetTester tester) async {
    // Build the app and trigger a frame
    await tester.pumpWidget(const VoltGuardApp());

    // Verify that the hero section content is displayed
    expect(find.text('Smart Energy\nManagement System'), findsOneWidget);
    expect(find.text('Monitor, analyze, and optimize your energy consumption\nwith AI-powered insights'), findsOneWidget);
    expect(find.byIcon(Icons.bolt), findsWidgets);
  });

  testWidgets('Landing page has Get Started button', (WidgetTester tester) async {
    // Build the app and trigger a frame
    await tester.pumpWidget(const VoltGuardApp());

    // Verify that the CTA buttons are present
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.text('Learn More'), findsOneWidget);
  });

  testWidgets('Landing page displays feature cards', (WidgetTester tester) async {
    // Build the app and trigger a frame
    await tester.pumpWidget(const VoltGuardApp());
    await tester.pumpAndSettle();

    // Scroll to make features visible
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();

    // Verify that feature titles are displayed
    expect(find.text('Real-time Monitoring'), findsOneWidget);
    expect(find.text('AI-Powered Predictions'), findsOneWidget);
    expect(find.text('Anomaly Detection'), findsOneWidget);
    expect(find.text('Fault Detection'), findsOneWidget);
  });

  testWidgets('Landing page has correct app bar', (WidgetTester tester) async {
    // Build the app and trigger a frame
    await tester.pumpWidget(const VoltGuardApp());

    // Verify that the app bar title is correct
    expect(find.text('Volt Guard'), findsWidgets);
  });

  testWidgets('Landing page displays stats', (WidgetTester tester) async {
    // Build the app and trigger a frame
    await tester.pumpWidget(const VoltGuardApp());

    // Verify that stats are displayed
    expect(find.text('10K+'), findsOneWidget);
    expect(find.text('Active Users'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('Energy Saved'), findsOneWidget);
  });

  testWidgets('Landing page displays benefits section', (WidgetTester tester) async {
    // Build the app and trigger a frame
    await tester.pumpWidget(const VoltGuardApp());
    await tester.pumpAndSettle();

    // Scroll to make benefits visible
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1500));
    await tester.pumpAndSettle();

    // Verify that benefits are displayed
    expect(find.text('Why Choose Volt Guard?'), findsOneWidget);
    expect(find.text('Save Money'), findsOneWidget);
    expect(find.text('Eco-Friendly'), findsOneWidget);
  });
}

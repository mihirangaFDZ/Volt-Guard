import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volt_guard/main.dart';

void main() {
  testWidgets('App displays welcome screen', (WidgetTester tester) async {
    // Build the app and trigger a frame
    await tester.pumpWidget(const VoltGuardApp());

    // Verify that the welcome screen elements are displayed
    expect(find.text('Volt Guard'), findsOneWidget);
    expect(find.text('Smart Energy Management'), findsOneWidget);
    expect(find.text('Monitor • Predict • Optimize'), findsOneWidget);
    expect(find.byIcon(Icons.energy_savings_leaf), findsOneWidget);
  });

  testWidgets('Welcome screen has Login and Sign Up buttons', (WidgetTester tester) async {
    // Build the app and trigger a frame
    await tester.pumpWidget(const VoltGuardApp());

    // Verify that buttons are displayed
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Sign Up'), findsOneWidget);
  });

  testWidgets('Login button navigates to login screen', (WidgetTester tester) async {
    // Build the app and trigger a frame
    await tester.pumpWidget(const VoltGuardApp());

    // Tap the login button
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    // Verify that we navigated to the login screen
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Sign in to continue'), findsOneWidget);
  });

  testWidgets('Sign Up button navigates to signup screen', (WidgetTester tester) async {
    // Build the app and trigger a frame
    await tester.pumpWidget(const VoltGuardApp());

    // Tap the sign up button
    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();

    // Verify that we navigated to the signup screen
    expect(find.text('Create Account'), findsOneWidget);
    expect(find.text('Sign up to get started'), findsOneWidget);
  });
}

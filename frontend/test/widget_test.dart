import 'package:flutter_test/flutter_test.dart';
import 'package:volt_guard/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Cold start routes to Login', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const VoltGuardApp());
    await tester.pumpAndSettle();

    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });

  testWidgets('Existing token still routes to Login',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'access_token': 'token'});
    await tester.pumpWidget(const VoltGuardApp());
    await tester.pumpAndSettle();

    expect(find.text('Welcome Back'), findsOneWidget);
  });
}

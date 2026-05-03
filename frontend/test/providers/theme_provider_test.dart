import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:volt_guard/providers/theme_provider.dart';

void main() {
  // Ensure bindings are initialised before using SharedPreferences mock.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ThemeProvider – initialisation', () {
    test('defaults to ThemeMode.system when no preference is stored', () async {
      final provider = ThemeProvider();
      // Immediately after construction the in-memory value is system.
      expect(provider.themeMode, equals(ThemeMode.system));
    });

    test('restores persisted ThemeMode.dark on construction', () async {
      // Pre-seed SharedPreferences with a stored value.
      SharedPreferences.setMockInitialValues({
        ThemeProvider.kThemeModeKey: 'dark',
      });

      final provider = ThemeProvider();
      // Allow the async _loadFromPrefs to complete.
      await Future<void>.delayed(Duration.zero);

      expect(provider.themeMode, equals(ThemeMode.dark));
    });

    test('restores persisted ThemeMode.light on construction', () async {
      SharedPreferences.setMockInitialValues({
        ThemeProvider.kThemeModeKey: 'light',
      });

      final provider = ThemeProvider();
      await Future<void>.delayed(Duration.zero);

      expect(provider.themeMode, equals(ThemeMode.light));
    });

    test('falls back to ThemeMode.system for an unrecognised stored value',
        () async {
      SharedPreferences.setMockInitialValues({
        ThemeProvider.kThemeModeKey: 'bogus_value',
      });

      final provider = ThemeProvider();
      await Future<void>.delayed(Duration.zero);

      expect(provider.themeMode, equals(ThemeMode.system));
    });
  });

  group('ThemeProvider – setThemeMode', () {
    test('updates themeMode and notifies listeners', () async {
      final provider = ThemeProvider();
      var notified = false;
      provider.addListener(() => notified = true);

      await provider.setThemeMode(ThemeMode.dark);

      expect(provider.themeMode, equals(ThemeMode.dark));
      expect(notified, isTrue);
    });

    test('does NOT notify listeners when mode is unchanged', () async {
      SharedPreferences.setMockInitialValues({
        ThemeProvider.kThemeModeKey: 'dark',
      });

      final provider = ThemeProvider();
      await Future<void>.delayed(Duration.zero); // let _loadFromPrefs run

      var notified = false;
      provider.addListener(() => notified = true);

      // Setting the same mode should be a no-op.
      await provider.setThemeMode(ThemeMode.dark);

      expect(notified, isFalse);
    });

    test('persists the selected mode to SharedPreferences', () async {
      final provider = ThemeProvider();
      await provider.setThemeMode(ThemeMode.light);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ThemeProvider.kThemeModeKey), equals('light'));
    });

    test('cycles through all three modes correctly', () async {
      final provider = ThemeProvider();

      await provider.setThemeMode(ThemeMode.light);
      expect(provider.themeMode, equals(ThemeMode.light));

      await provider.setThemeMode(ThemeMode.dark);
      expect(provider.themeMode, equals(ThemeMode.dark));

      await provider.setThemeMode(ThemeMode.system);
      expect(provider.themeMode, equals(ThemeMode.system));
    });
  });

  group('ThemeProvider – helpers', () {
    test('labelFor returns human-readable strings', () {
      expect(ThemeProvider.labelFor(ThemeMode.system), 'System default');
      expect(ThemeProvider.labelFor(ThemeMode.light), 'Light');
      expect(ThemeProvider.labelFor(ThemeMode.dark), 'Dark');
    });

    test('iconFor returns distinct icons for each mode', () {
      final system = ThemeProvider.iconFor(ThemeMode.system);
      final light = ThemeProvider.iconFor(ThemeMode.light);
      final dark = ThemeProvider.iconFor(ThemeMode.dark);

      expect(system, isNot(equals(light)));
      expect(light, isNot(equals(dark)));
      expect(system, isNot(equals(dark)));
    });
  });

  group('AppTheme – theme data smoke tests', () {
    test('ThemeMode enum has exactly 3 values', () {
      expect(ThemeMode.values.length, equals(3));
    });

    test('kThemeModeKey is non-empty', () {
      expect(ThemeProvider.kThemeModeKey, isNotEmpty);
    });
  });
}

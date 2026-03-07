import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages [ThemeMode] and persists the preference to [SharedPreferences]
/// under the key [kThemeModeKey].
class ThemeProvider extends ChangeNotifier {
  static const String kThemeModeKey = 'theme_mode';

  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  ThemeProvider() {
    _loadFromPrefs();
  }

  // ─── Persistence ────────────────────────────────────────────────────────────

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(kThemeModeKey);
    if (stored != null) {
      _themeMode = ThemeMode.values.firstWhere(
        (e) => e.name == stored,
        orElse: () => ThemeMode.system,
      );
      notifyListeners();
    }
  }

  Future<void> _saveToPrefs(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kThemeModeKey, mode.name);
  }

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Updates the active [ThemeMode] and persists the choice.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await _saveToPrefs(mode);
  }

  /// Human-readable label for [ThemeMode] values.
  static String labelFor(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'System default';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }

  /// Icon associated with each [ThemeMode].
  static IconData iconFor(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return Icons.brightness_auto_outlined;
      case ThemeMode.light:
        return Icons.light_mode_outlined;
      case ThemeMode.dark:
        return Icons.dark_mode_outlined;
    }
  }
}

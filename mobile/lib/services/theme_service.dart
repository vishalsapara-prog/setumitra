import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The 5 predefined themes from the approved requirements, in the exact
/// order and names specified. Switching themes changes appearance ONLY --
/// no data or functionality is affected, per the explicit requirement
/// ("Theme બદલવાથી data/functionality બદલાવું નહીં જોઈએ").
enum SetumitraTheme { professionalBlue, classicLight, modernTeal, dark, highContrast }

extension SetumitraThemeLabel on SetumitraTheme {
  String get label {
    switch (this) {
      case SetumitraTheme.professionalBlue:
        return 'Professional Blue';
      case SetumitraTheme.classicLight:
        return 'Classic Light';
      case SetumitraTheme.modernTeal:
        return 'Modern Teal';
      case SetumitraTheme.dark:
        return 'Dark';
      case SetumitraTheme.highContrast:
        return 'High Contrast';
    }
  }

  static SetumitraTheme fromLabel(String label) {
    return SetumitraTheme.values.firstWhere(
      (t) => t.label == label,
      orElse: () => SetumitraTheme.professionalBlue,
    );
  }
}

class ThemeService {
  static const String _prefsKey = 'setumitra_theme';

  /// Default is Professional Blue, per the explicit requirement.
  static Future<SetumitraTheme> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    if (stored == null) return SetumitraTheme.professionalBlue;
    return SetumitraThemeLabel.fromLabel(stored);
  }

  static Future<void> saveTheme(SetumitraTheme theme) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, theme.label);
  }

  static ThemeData themeDataFor(SetumitraTheme theme) {
    switch (theme) {
      case SetumitraTheme.professionalBlue:
        return _build(
          seed: const Color(0xFF2B6CB0),
          primary: const Color(0xFF1A365D),
          scaffoldBg: const Color(0xFFFAFAFA),
          brightness: Brightness.light,
        );
      case SetumitraTheme.classicLight:
        return _build(
          seed: const Color(0xFF6B7280),
          primary: const Color(0xFF374151),
          scaffoldBg: const Color(0xFFFFFFFF),
          brightness: Brightness.light,
        );
      case SetumitraTheme.modernTeal:
        return _build(
          seed: const Color(0xFF0D9488),
          primary: const Color(0xFF0F766E),
          scaffoldBg: const Color(0xFFF0FDFA),
          brightness: Brightness.light,
        );
      case SetumitraTheme.dark:
        return _build(
          seed: const Color(0xFF60A5FA),
          primary: const Color(0xFF1E293B),
          scaffoldBg: const Color(0xFF0F172A),
          brightness: Brightness.dark,
        );
      case SetumitraTheme.highContrast:
        return _build(
          seed: const Color(0xFFFFD400),
          primary: const Color(0xFF000000),
          scaffoldBg: const Color(0xFFFFFFFF),
          brightness: Brightness.light,
          highContrast: true,
        );
    }
  }

  static ThemeData _build({
    required Color seed,
    required Color primary,
    required Color scaffoldBg,
    required Brightness brightness,
    bool highContrast = false,
  }) {
    final colorScheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: highContrast
          ? colorScheme.copyWith(
              primary: Colors.black,
              onPrimary: Colors.white,
              secondary: const Color(0xFFFFD400),
              surface: Colors.white,
              onSurface: Colors.black,
            )
          : colorScheme,
      primaryColor: primary,
      scaffoldBackgroundColor: scaffoldBg,
      appBarTheme: AppBarTheme(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: highContrast ? 0 : 2,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: highContrast ? Colors.black : colorScheme.secondary,
        foregroundColor: highContrast ? const Color(0xFFFFD400) : null,
      ),
      cardTheme: CardThemeData(
        elevation: highContrast ? 0 : 1,
        shape: highContrast
            ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: const BorderSide(color: Colors.black, width: 1.5))
            : null,
      ),
    );
  }
}

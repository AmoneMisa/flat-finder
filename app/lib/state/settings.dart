import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/strings.dart';

/// The selectable app themes. `light` is the default; the two dark variants
/// differ in their seed/surface colour.
const kThemeOptions = ['light', 'dark', 'darkBlue'];

/// Build the [ThemeData] for a named theme (see [kThemeOptions]). Kept as a
/// free function so [main] can drive `MaterialApp.theme` from the current
/// setting without duplicating the colour definitions.
ThemeData buildTheme(String name) {
  const seed = Color(0xFF2E7D6B);
  switch (name) {
    case 'dark':
      return ThemeData(
        useMaterial3: true,
        colorSchemeSeed: seed,
        brightness: Brightness.dark,
      );
    case 'darkBlue':
      final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF3D5AFE),
        brightness: Brightness.dark,
      ).copyWith(
        surface: const Color(0xFF0E1730),
        surfaceContainerHighest: const Color(0xFF1B2745),
      );
      return ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFF0A1226),
      );
    case 'light':
    default:
      return ThemeData(
        useMaterial3: true,
        colorSchemeSeed: seed,
        brightness: Brightness.light,
      );
  }
}

/// User preferences: UI language and the currency prices are displayed in.
/// Persisted with SharedPreferences so choices survive app restarts.
class SettingsState extends ChangeNotifier {
  static const _kLang = 'lang';
  static const _kCurrency = 'displayCurrency';
  static const _kTheme = 'theme';

  /// Currencies the user can normalize prices into. `null` keeps each listing's
  /// own currency.
  static const currencyOptions = [null, 'EUR', 'USD', 'RON', 'UAH', 'KZT', 'UZS'];

  String lang = 'en';
  String? displayCurrency; // null = native
  String themeName = 'light'; // one of kThemeOptions

  AppStrings get s => AppStrings(lang);
  Locale get locale => Locale(lang);
  String t(String key, [Map<String, String>? params]) => s.t(key, params);
  ThemeData get themeData => buildTheme(themeName);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    lang = p.getString(_kLang) ?? 'en';
    if (!AppStrings.supported.contains(lang)) lang = 'en';
    displayCurrency = p.getString(_kCurrency);
    final t = p.getString(_kTheme);
    if (t != null && kThemeOptions.contains(t)) themeName = t;
    notifyListeners();
  }

  Future<void> setTheme(String value) async {
    if (themeName == value || !kThemeOptions.contains(value)) return;
    themeName = value;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kTheme, value);
  }

  Future<void> setLang(String value) async {
    if (lang == value) return;
    lang = value;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLang, value);
  }

  Future<void> setDisplayCurrency(String? value) async {
    displayCurrency = value;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    if (value == null) {
      await p.remove(_kCurrency);
    } else {
      await p.setString(_kCurrency, value);
    }
  }
}

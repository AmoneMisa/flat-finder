import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/strings.dart';

/// The selectable app themes. `light` is the default; the two dark variants
/// differ in their seed/surface colour.
const kThemeOptions = ['light', 'dark', 'darkBlue'];

/// whiteslove.me's design tokens (`--color-primary`, `--bg-*`, `--text-*`,
/// `--flat-tone-*`...), pulled from its live `:root` custom properties so the
/// app reads as the same product as the site rather than a generic Material
/// palette. Keep these in sync if the site's tokens change.
class BrandColors {
  const BrandColors._();

  static const primary = Color(0xFFE0679A); // --color-primary / --accent-pink
  static const primaryAlt = Color(0xFF35316F); // --color-primary-alt
  static const secondary = Color(0xFFCD99FF); // --color-secondary
  static const accentBlue = Color(0xFF7189D9); // --accent-blue

  static const bgDeep = Color(0xFF0D1128); // --bg-deep
  static const bgPanel = Color(0xFF131730); // --bg-panel
  static const bgPanel2 = Color(0xFF171C3A); // --bg-panel-2
  static const line = Color(0xFF252A4A); // --line

  static const textPrimary = Color(0xFFEEF0F7); // --text-primary
  static const textSoft = Color(0xFFC8CCDF); // --text-soft
  static const textMuted = Color(0xFF9EA4C1); // --text-muted

  // --flat-tone-* — this product's own status/badge palette on the site.
  static const toneGreen = Color(0xFF4ADE80);
  static const toneBlue = Color(0xFF67E8F9);
  static const tonePink = Color(0xFFE0679A);
  static const toneOrange = Color(0xFFFB923C);
  static const toneYellow = Color(0xFFFACC15);
  static const toneRed = Color(0xFFEF4444);

  static const radius = 10.0; // --radius
}

InputDecorationTheme _brandInputTheme(Color accent) => InputDecorationTheme(
  filled: true,
  fillColor: BrandColors.bgPanel,
  hintStyle: const TextStyle(color: BrandColors.textMuted),
  labelStyle: const TextStyle(color: BrandColors.textSoft),
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(BrandColors.radius),
    borderSide: const BorderSide(color: BrandColors.line),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(BrandColors.radius),
    borderSide: const BorderSide(color: BrandColors.line),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(BrandColors.radius),
    borderSide: BorderSide(color: accent, width: 2),
  ),
);

/// Build the [ThemeData] for a named theme (see [kThemeOptions]). Kept as a
/// free function so [main] can drive `MaterialApp.theme` from the current
/// setting without duplicating the colour definitions.
ThemeData buildTheme(String name) {
  switch (name) {
    case 'dark':
      // The site's actual palette: navy/near-black with a single pink accent.
      final scheme =
          ColorScheme.fromSeed(
            seedColor: BrandColors.primary,
            brightness: Brightness.dark,
            secondary: BrandColors.secondary,
          ).copyWith(
            primary: BrandColors.primary,
            secondary: BrandColors.secondary,
            surface: BrandColors.bgPanel,
            surfaceContainerHighest: BrandColors.bgPanel2,
            onSurface: BrandColors.textPrimary,
            outline: BrandColors.line,
          );
      return ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: BrandColors.bgDeep,
        brightness: Brightness.dark,
        inputDecorationTheme: _brandInputTheme(BrandColors.primary),
        appBarTheme: const AppBarTheme(
          backgroundColor: BrandColors.bgDeep,
          foregroundColor: BrandColors.textPrimary,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: BrandColors.bgPanel,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: BrandColors.line),
            borderRadius: BorderRadius.circular(BrandColors.radius),
          ),
        ),
      );
    case 'darkBlue':
      // Same dark surfaces, blue accent instead of pink — an on-brand
      // alternative to the site's default rather than an unrelated hue.
      final scheme =
          ColorScheme.fromSeed(
            seedColor: BrandColors.accentBlue,
            brightness: Brightness.dark,
            secondary: BrandColors.secondary,
          ).copyWith(
            primary: BrandColors.accentBlue,
            secondary: BrandColors.secondary,
            surface: BrandColors.bgPanel,
            surfaceContainerHighest: BrandColors.bgPanel2,
            onSurface: BrandColors.textPrimary,
            outline: BrandColors.line,
          );
      return ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: BrandColors.bgDeep,
        brightness: Brightness.dark,
        inputDecorationTheme: _brandInputTheme(BrandColors.accentBlue),
        appBarTheme: const AppBarTheme(
          backgroundColor: BrandColors.bgDeep,
          foregroundColor: BrandColors.textPrimary,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: BrandColors.bgPanel,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: BrandColors.line),
            borderRadius: BorderRadius.circular(BrandColors.radius),
          ),
        ),
      );
    case 'light':
    default:
      // The site itself is dark-only; this is the same pink/purple brand
      // hues carried onto a light surface for users who prefer light mode.
      final scheme =
          ColorScheme.fromSeed(
            seedColor: BrandColors.primary,
            brightness: Brightness.light,
            secondary: BrandColors.primaryAlt,
          ).copyWith(
            primary: BrandColors.primary,
            secondary: BrandColors.primaryAlt,
          );
      return ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
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
  static const currencyOptions = [
    null,
    'EUR',
    'USD',
    'RON',
    'UAH',
    'KZT',
    'UZS',
  ];

  String lang = 'en';
  String? displayCurrency; // null = native
  String themeName = 'dark'; // the web frontend is dark-first

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

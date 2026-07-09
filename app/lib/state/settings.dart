import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/strings.dart';

/// User preferences: UI language and the currency prices are displayed in.
/// Persisted with SharedPreferences so choices survive app restarts.
class SettingsState extends ChangeNotifier {
  static const _kLang = 'lang';
  static const _kCurrency = 'displayCurrency';

  /// Currencies the user can normalize prices into. `null` keeps each listing's
  /// own currency.
  static const currencyOptions = [null, 'EUR', 'USD', 'RON', 'UAH', 'KZT', 'UZS'];

  String lang = 'en';
  String? displayCurrency; // null = native

  AppStrings get s => AppStrings(lang);
  Locale get locale => Locale(lang);
  String t(String key, [Map<String, String>? params]) => s.t(key, params);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    lang = p.getString(_kLang) ?? 'en';
    if (!AppStrings.supported.contains(lang)) lang = 'en';
    displayCurrency = p.getString(_kCurrency);
    notifyListeners();
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

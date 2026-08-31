from pathlib import Path

path = Path('app/lib/state/app_state.dart')
text = path.read_text(encoding='utf-8')

old = """  String _countriesLocale = '';\n  String? _countriesLocaleLoading;\n"""
new = """  static const _countriesLocaleRetryDelay = Duration(seconds: 30);\n\n  String _countriesLocale = '';\n  String? _countriesLocaleLoading;\n  String? _countriesLocaleFailed;\n  DateTime? _countriesLocaleRetryAfter;\n"""
if old not in text:
    raise SystemExit('locale state block not found')
text = text.replace(old, new, 1)

old = """  Future<void> ensureCountriesLocale(String locale) async {\n    if (locale == _countriesLocale ||\n        locale == _countriesLocaleLoading ||\n        countries.isEmpty) {\n      return;\n    }\n    _countriesLocaleLoading = locale;\n    try {\n      final localized = await _api.fetchCountries(locale: locale);\n      if (locale != _countriesLocaleLoading) return; // superseded\n      countries = localized;\n      _countriesLocale = locale;\n      notifyListeners();\n    } catch (_) {\n      // Do not mark the locale as loaded after a transient failure. The next\n      // build can retry instead of leaving raw canonical names forever.\n    } finally {\n      if (_countriesLocaleLoading == locale) _countriesLocaleLoading = null;\n    }\n  }\n"""
new = """  Future<void> ensureCountriesLocale(String locale) async {\n    final retryBlocked = locale == _countriesLocaleFailed &&\n        _countriesLocaleRetryAfter != null &&\n        DateTime.now().isBefore(_countriesLocaleRetryAfter!);\n    if (locale == _countriesLocale ||\n        locale == _countriesLocaleLoading ||\n        retryBlocked ||\n        countries.isEmpty) {\n      return;\n    }\n    _countriesLocaleLoading = locale;\n    try {\n      final localized = await _api.fetchCountries(locale: locale);\n      if (locale != _countriesLocaleLoading) return; // superseded\n      countries = localized;\n      _countriesLocale = locale;\n      _countriesLocaleFailed = null;\n      _countriesLocaleRetryAfter = null;\n      notifyListeners();\n    } catch (_) {\n      // A build-triggered retry must not become a tight request loop during a\n      // transient outage. Keep the raw canonical labels and retry this locale\n      // after a short cooldown; a different locale is still allowed instantly.\n      if (_countriesLocaleLoading == locale) {\n        _countriesLocaleFailed = locale;\n        _countriesLocaleRetryAfter =\n            DateTime.now().add(_countriesLocaleRetryDelay);\n      }\n    } finally {\n      if (_countriesLocaleLoading == locale) _countriesLocaleLoading = null;\n    }\n  }\n"""
if old not in text:
    raise SystemExit('ensureCountriesLocale block not found')
text = text.replace(old, new, 1)

path.write_text(text, encoding='utf-8')

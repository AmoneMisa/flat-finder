import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/filters.dart';
import '../models/listing.dart';
import '../services/api_service.dart';

class AppState extends ChangeNotifier {
  AppState(this._api);

  static const _kFilters = 'filters';

  final ApiService _api;

  List<Country> countries = [];
  Filters filters = Filters();
  List<Listing> listings = [];
  List<Listing> mapListings = [];
  List<String> degradedCountries = [];
  List<SourceError> sourceErrors =
      []; // per-source failures from the last search
  Map<String, double> rates = {}; // currency -> units per 1 USD

  bool loading = false;
  bool loadingMore = false;
  bool mapLoading = false;
  String? error;
  String? nextCursor;
  int total = 0;
  int _searchGeneration = 0;

  // Client-side cooldown for the manual "Reload all" button, matching the
  // server's flood protection so the button greys out instead of hitting a 429.
  DateTime? _reloadAllUntil;
  Timer? _reloadAllTimer;
  bool get reloadAllCoolingDown =>
      _reloadAllUntil != null && DateTime.now().isBefore(_reloadAllUntil!);

  @override
  void dispose() {
    _reloadAllTimer?.cancel();
    super.dispose();
  }

  String _countriesLocale = '';

  Future<void> init() async {
    // Restore the user's last-used filters (country, type, price, etc.) so the
    // app reopens where they left off.
    await _loadFilters();

    // Rates are non-critical: fetch best-effort so a failure never blocks search.
    _api
        .fetchRates()
        .then((r) {
          rates = r;
          notifyListeners();
        })
        .catchError((_) {});
    try {
      countries = await _api.fetchCountries();
      if (countries.isNotEmpty && filters.countries.isEmpty) {
        filters = filters.copyWith(countries: {countries.first.code});
      }
      notifyListeners();
      await search();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  /// Re-fetches [countries] with localized city/district/metro/etc. labels
  /// once the UI language is known (or changes) — `init()` runs before
  /// SettingsState finishes loading the saved language, so it always starts
  /// with unlocalized (raw) names. Cheap to call from `build()`: no-ops once
  /// already fetched for this locale.
  Future<void> ensureCountriesLocale(String locale) async {
    if (locale == _countriesLocale || countries.isEmpty) return;
    _countriesLocale = locale;
    try {
      final localized = await _api.fetchCountries(locale: locale);
      if (locale != _countriesLocale) return; // superseded by a newer call
      countries = localized;
      notifyListeners();
    } catch (_) {
      // Keep the unlocalized list rather than surfacing an error for what's
      // a display-only enhancement.
    }
  }

  Future<void> _loadFilters() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kFilters);
      if (raw != null) {
        filters = Filters.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      // Corrupt/incompatible saved state: fall back to defaults silently.
    }
  }

  Future<void> _saveFilters() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kFilters, jsonEncode(filters.toJson()));
    } catch (_) {}
  }

  Country? countryByCode(String code) {
    for (final c in countries) {
      if (c.code == code) return c;
    }
    return null;
  }

  void updateFilters(Filters next) {
    filters = next;
    notifyListeners();
    _saveFilters(); // persist so choices survive restarts
  }

  /// Validate a candidate custom-source URL against the backend (uses the first
  /// selected country for currency/context).
  Future<SourceValidation> validateSource(String url) {
    final country = filters.countries.isNotEmpty
        ? filters.countries.first
        : null;
    return _api.validateSource(url, country: country);
  }

  void addCustomSource(String url) {
    final u = url.trim();
    if (u.isEmpty || filters.customSources.contains(u)) return;
    updateFilters(
      filters.copyWith(customSources: [...filters.customSources, u]),
    );
  }

  void removeCustomSource(String url) {
    updateFilters(
      filters.copyWith(
        customSources: filters.customSources.where((s) => s != url).toList(),
      ),
    );
  }

  Future<void> search() async {
    final generation = ++_searchGeneration;
    if (filters.countries.isEmpty) {
      listings = [];
      nextCursor = null;
      total = 0;
      error = 'Select at least one country';
      notifyListeners();
      return;
    }
    loading = true;
    mapListings = [];
    error = null;
    notifyListeners();
    try {
      final res = await _api.fetchListings(filters);
      if (generation != _searchGeneration) return;
      listings = res.listings;
      nextCursor = res.nextCursor;
      total = res.total;
      degradedCountries = res.degradedCountries;
      sourceErrors = res.sourceErrors;
    } catch (e) {
      if (generation != _searchGeneration) return;
      error = e.toString();
      listings = [];
      nextCursor = null;
      total = 0;
      sourceErrors = [];
    } finally {
      if (generation == _searchGeneration) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore() async {
    final cursor = nextCursor;
    if (loading || loadingMore || cursor == null || cursor.isEmpty) return;
    final generation = _searchGeneration;
    loadingMore = true;
    notifyListeners();
    try {
      final res = await _api.fetchListings(filters, cursor: cursor);
      if (generation != _searchGeneration) return;
      final seen = listings.map((item) => '${item.source}:${item.id}').toSet();
      listings = [
        ...listings,
        ...res.listings.where((item) => seen.add('${item.source}:${item.id}')),
      ];
      nextCursor = res.nextCursor;
      total = res.total;
    } catch (e) {
      if (generation == _searchGeneration) error = e.toString();
    } finally {
      if (generation == _searchGeneration) {
        loadingMore = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMapListings() async {
    if (mapLoading || filters.countries.isEmpty) return;
    final generation = _searchGeneration;
    mapLoading = true;
    notifyListeners();
    try {
      final points = await _api.fetchMapListings(filters);
      if (generation == _searchGeneration) mapListings = points;
    } finally {
      if (generation == _searchGeneration) {
        mapLoading = false;
        notifyListeners();
      }
    }
  }

  /// Force a fresh scrape (bypasses the backend cache), then start a local
  /// cooldown so the button can't be spammed into the server's 429.
  Future<void> reloadAll() async {
    if (loading || reloadAllCoolingDown || filters.countries.isEmpty) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final res = await _api.fetchListings(filters, force: true);
      listings = res.listings;
      nextCursor = res.nextCursor;
      total = res.total;
      degradedCountries = res.degradedCountries;
      sourceErrors = res.sourceErrors;
      _startReloadAllCooldown(const Duration(seconds: 8));
    } on RateLimitException catch (e) {
      _startReloadAllCooldown(Duration(milliseconds: e.retryAfterMs));
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void _startReloadAllCooldown(Duration d) {
    _reloadAllUntil = DateTime.now().add(d);
    _reloadAllTimer?.cancel();
    // Re-enable the button (refresh the UI) once the cooldown elapses.
    _reloadAllTimer = Timer(d, () {
      _reloadAllUntil = null;
      notifyListeners();
    });
  }

  /// Re-fetch one listing fresh and, if it's still in the current results,
  /// swap in the updated copy. Returns the fresh listing (or null if gone).
  Future<Listing?> reloadListing(Listing l) async {
    final fresh = await _api.reloadListing(l);
    if (fresh != null) {
      final i = listings.indexWhere(
        (x) => x.id == l.id && x.source == l.source,
      );
      if (i >= 0) {
        listings[i] = fresh;
        notifyListeners();
      }
    }
    return fresh;
  }

  /// Translate text into the currently selected UI language. The service uses
  /// asynchronous submit + polling, so a long Ollama inference is not tied to a
  /// single HTTP request and transient transport timeouts do not discard it.
  Future<String> translateText(String text, {required String targetLanguage}) {
    return _api.translateText(text, targetLanguage: targetLanguage);
  }
}

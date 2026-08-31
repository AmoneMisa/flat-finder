import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/filters.dart';
import '../models/listing.dart';
import '../models/listing_identity.dart';
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
  String? _countriesLocaleLoading;

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
    if (locale == _countriesLocale ||
        locale == _countriesLocaleLoading ||
        countries.isEmpty) {
      return;
    }
    _countriesLocaleLoading = locale;
    try {
      final localized = await _api.fetchCountries(locale: locale);
      if (locale != _countriesLocaleLoading) return; // superseded
      countries = localized;
      _countriesLocale = locale;
      notifyListeners();
    } catch (_) {
      // Do not mark the locale as loaded after a transient failure. The next
      // build can retry instead of leaving raw canonical names forever.
    } finally {
      if (_countriesLocaleLoading == locale) _countriesLocaleLoading = null;
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

  String _filterFingerprint(Filters value) {
    final payload = Map<String, dynamic>.from(value.toJson());
    for (final key in const [
      'countries',
      'sources',
      'customSources',
      'amenities',
    ]) {
      final values = (payload[key] as List? ?? const [])
          .map((item) => item.toString())
          .toList()
        ..sort();
      payload[key] = values;
    }
    return jsonEncode(payload);
  }

  bool _sameFilterPayload(Filters a, Filters b) =>
      _filterFingerprint(a) == _filterFingerprint(b);

  bool _sameLocationScope(Filters a, Filters b) =>
      setEquals(a.countries, b.countries) &&
      a.city == b.city &&
      a.district == b.district &&
      a.microdistrict == b.microdistrict &&
      a.quartal == b.quartal &&
      a.area == b.area &&
      a.metro == b.metro;

  bool _sameRadius(Filters a, Filters b) =>
      a.centerLat == b.centerLat &&
      a.centerLng == b.centerLng &&
      a.radiusM == b.radiusM;

  /// Normalizes filter updates coming from controls that do not expose every
  /// field. The advanced sheet, for example, builds a fresh [Filters] object
  /// without map radius or price-tolerance fields. Those hidden values survive
  /// unrelated edits, but changing the geographic scope invalidates an old map
  /// radius and changing the visible price range invalidates an inherited
  /// tolerance. Returns whether the effective filter payload actually changed.
  bool updateFilters(Filters next) {
    final current = filters;
    var normalized = next;

    final locationChanged = !_sameLocationScope(current, next);
    final radiusWasImplicitlyCarried = _sameRadius(current, next);
    final radiusWasOmitted =
        next.centerLat == null && next.centerLng == null && next.radiusM == null;
    final currentHasRadius = current.centerLat != null ||
        current.centerLng != null ||
        current.radiusM != null;

    if (locationChanged && radiusWasImplicitlyCarried && currentHasRadius) {
      // copyWith() preserves radius fields by default; an explicit country/city/
      // district change must not keep searching around the old map point.
      normalized = normalized.copyWith(clearRadiusSearch: true);
    } else if (!locationChanged && radiusWasOmitted && currentHasRadius) {
      // A control that simply does not model radius search must not erase it.
      normalized = normalized.copyWith(
        centerLat: current.centerLat,
        centerLng: current.centerLng,
        radiusM: current.radiusM,
      );
    }

    final priceScopeChanged = normalized.priceMin != current.priceMin ||
        normalized.priceMax != current.priceMax ||
        normalized.priceCurrency != current.priceCurrency;
    final toleranceWasImplicitlyCarried =
        normalized.priceTolerance == current.priceTolerance;
    if (priceScopeChanged &&
        toleranceWasImplicitlyCarried &&
        current.priceTolerance != null) {
      normalized = normalized.copyWith(clearPriceTolerance: true);
    } else if (!priceScopeChanged &&
        normalized.priceTolerance == null &&
        current.priceTolerance != null) {
      normalized = normalized.copyWith(priceTolerance: current.priceTolerance);
    }

    if (_sameFilterPayload(current, normalized)) return false;
    filters = normalized;
    notifyListeners();
    _saveFilters(); // persist so choices survive restarts
    return true;
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

  /// Drops a listing confirmed gone by a live source re-check (e.g. an OLX
  /// advert taken down since the last crawl) from the current result set —
  /// mirrors the web's `removeUnavailableListing`.
  void removeListing(String source, String country, String id) {
    final before = listings.length;
    listings = listings
        .where(
          (l) => !(l.source == source && l.country == country && l.id == id),
        )
        .toList();
    if (listings.length != before) notifyListeners();
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
      final seen = listings.map(listingKey).toSet();
      listings = [
        ...listings,
        ...res.listings.where((item) => seen.add(listingKey(item))),
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
  /// cooldown so the button can't be spammed into the server's 429. This is a
  /// search generation too: if filters change while the force request is in
  /// flight, its stale result must not overwrite the newer filtered search.
  Future<void> reloadAll() async {
    if (loading || reloadAllCoolingDown || filters.countries.isEmpty) return;
    final generation = ++_searchGeneration;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final res = await _api.fetchListings(filters, force: true);
      if (generation != _searchGeneration) return;
      listings = res.listings;
      nextCursor = res.nextCursor;
      total = res.total;
      degradedCountries = res.degradedCountries;
      sourceErrors = res.sourceErrors;
      _startReloadAllCooldown(const Duration(seconds: 8));
    } on RateLimitException catch (e) {
      if (generation == _searchGeneration) {
        _startReloadAllCooldown(Duration(milliseconds: e.retryAfterMs));
      }
    } catch (e) {
      if (generation == _searchGeneration) error = e.toString();
    } finally {
      if (generation == _searchGeneration) {
        loading = false;
        notifyListeners();
      }
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
  Future<Listing?> reloadListing(Listing listing) async {
    final fresh = await _api.reloadListing(listing);
    if (fresh != null) {
      final i = listings.indexWhere((item) => sameListing(item, listing));
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

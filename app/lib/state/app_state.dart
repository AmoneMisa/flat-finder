import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/district_zone.dart';
import '../models/filters.dart';
import '../models/listing.dart';
import '../models/listing_identity.dart';
import '../models/map_listing_point.dart';
import '../services/api_service.dart';
import '../utils/metro_proximity.dart';

/// A response held for [_feedCacheTtl] and keyed by the exact filter
/// combination that produced it, so re-visiting a combination -- most often a
/// checkbox toggled off and back on -- repaints instantly instead of paying
/// for another round trip. Mirrors the same cache added to the web client.
class _CacheEntry<T> {
  _CacheEntry(this.value) : at = DateTime.now();
  final T value;
  final DateTime at;
}

class AppState extends ChangeNotifier {
  AppState(this._api);

  static const _kFilters = 'filters';
  static const _searchDebounce = Duration(milliseconds: 250);
  static const _feedCacheTtl = Duration(seconds: 60);
  static const _feedCacheMaxEntries = 40;

  final ApiService _api;
  final _listingsCache = <String, _CacheEntry<ListingsResult>>{};
  final _mapCache = <String, _CacheEntry<List<MapListingPoint>>>{};

  // Metro station coordinates for the proximity filter below. The backend
  // has no endpoint for "just these station names' coordinates" -- only the
  // full per-city geography catalog (districts, microdistricts, POIs, metro
  // together) that the map screen also loads. Cached per city so switching
  // filters back and forth doesn't refetch it, and never fetched at all
  // unless a metro filter is actually active.
  MapZones _metroZones = const MapZones();
  String _metroZonesKey = '';

  Future<MapZones> _zonesForMetroProximity(Filters filters) async {
    if (filters.metro.isEmpty) return const MapZones();
    final country = filters.countries.isEmpty ? '' : filters.countries.first;
    if (country.isEmpty || filters.city.isEmpty) return const MapZones();
    final key = '$country|${filters.city}';
    if (key == _metroZonesKey) return _metroZones;
    final zones = await _api.fetchMapZones(country, filters.city);
    _metroZonesKey = key;
    _metroZones = zones;
    return zones;
  }

  /// Built from the *live* filter set against whatever station coordinates
  /// are cached -- if a station's coordinates never arrived (offline, or a
  /// city the zones fetch hasn't covered yet), that station simply drops out
  /// of the filter rather than the whole search failing.
  ///
  /// The distance limit is enforced here only when more than one station is
  /// selected. With exactly one, the backend already narrowed by metroMaxM
  /// (see Filters.toUpstreamQueryParams), and re-checking coordinates the
  /// feed may not carry for every listing would drop results the server
  /// deliberately kept. The arc has no backend equivalent at all and is
  /// always enforced here, regardless of station count. Mirrors the web
  /// client's useMetroProximity.ts exactly.
  MetroProximity _metroProximityFor(Filters filters, MapZones zones) {
    if (filters.metro.isEmpty) return const MetroProximity();
    final stations = [
      for (final name in filters.metro)
        for (final zone in zones.metroStations)
          if (zone.name == name)
            MetroPoint(name: zone.name, lat: zone.lat, lng: zone.lng),
    ];
    return MetroProximity(
      stations: stations,
      maxM: filters.metro.length > 1 ? filters.metroMaxM?.toDouble() : null,
      bearingFrom: filters.metroBearingFrom?.toDouble(),
      bearingTo: filters.metroBearingTo?.toDouble(),
    );
  }

  List<Listing> _narrowListingsByMetro(
    List<Listing> items,
    MetroProximity proximity,
  ) =>
      applyMetroProximity(
        items,
        proximity,
        (item) => item.hasLocation ? LatLng(item.lat!, item.lng!) : null,
      );

  List<MapListingPoint> _narrowMapPointsByMetro(
    List<MapListingPoint> items,
    MetroProximity proximity,
  ) =>
      applyMetroProximity(
        items,
        proximity,
        (item) => LatLng(item.lat, item.lng),
      );

  /// Stable regardless of the order [Filters.toQueryParams] happened to build
  /// its map in.
  String _cacheKey(Filters f) {
    final params = f.toQueryParams();
    final keys = params.keys.toList()..sort();
    return keys.map((k) => '$k=${params[k]}').join('&');
  }

  T? _readCache<T>(Map<String, _CacheEntry<T>> cache, String key) {
    final entry = cache[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.at) > _feedCacheTtl) {
      cache.remove(key);
      return null;
    }
    return entry.value;
  }

  void _writeCache<T>(Map<String, _CacheEntry<T>> cache, String key, T value) {
    cache.remove(key);
    cache[key] = _CacheEntry(value);
    while (cache.length > _feedCacheMaxEntries) {
      cache.remove(cache.keys.first);
    }
  }

  List<Country> countries = [];
  Filters filters = Filters();
  List<Listing> listings = [];
  List<MapListingPoint> mapListings = [];
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
  Timer? _searchDebounceTimer;
  Completer<void>? _pendingSearchCompletion;

  // Client-side cooldown for the manual "Reload all" button, matching the
  // server's flood protection so the button greys out instead of hitting a 429.
  DateTime? _reloadAllUntil;
  Timer? _reloadAllTimer;
  bool get reloadAllCoolingDown =>
      _reloadAllUntil != null && DateTime.now().isBefore(_reloadAllUntil!);

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    final pending = _pendingSearchCompletion;
    if (pending != null && !pending.isCompleted) pending.complete();
    _api.cancelListingRequests();
    _reloadAllTimer?.cancel();
    super.dispose();
  }

  static const _countriesLocaleRetryDelay = Duration(seconds: 30);

  String _countriesLocale = '';
  String? _countriesLocaleLoading;
  String? _countriesLocaleFailed;
  DateTime? _countriesLocaleRetryAfter;

  Future<void> init() async {
    // Restore the user's last-used filters (country, type, price, etc.) so the
    // app reopens where they left off.
    await _loadFilters();

    // Rates are non-critical: fetch best-effort so a failure never blocks search.
    _api.fetchRates().then((r) {
      rates = r;
      notifyListeners();
    }).catchError((_) {});
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
    final retryBlocked = locale == _countriesLocaleFailed &&
        _countriesLocaleRetryAfter != null &&
        DateTime.now().isBefore(_countriesLocaleRetryAfter!);
    if (locale == _countriesLocale ||
        locale == _countriesLocaleLoading ||
        retryBlocked ||
        countries.isEmpty) {
      return;
    }
    _countriesLocaleLoading = locale;
    try {
      final localized = await _api.fetchCountries(locale: locale);
      if (locale != _countriesLocaleLoading) return; // superseded
      countries = localized;
      _countriesLocale = locale;
      _countriesLocaleFailed = null;
      _countriesLocaleRetryAfter = null;
      notifyListeners();
    } catch (_) {
      // A build-triggered retry must not become a tight request loop during a
      // transient outage. Keep the raw canonical labels and retry this locale
      // after a short cooldown; a different locale is still allowed instantly.
      if (_countriesLocaleLoading == locale) {
        _countriesLocaleFailed = locale;
        _countriesLocaleRetryAfter =
            DateTime.now().add(_countriesLocaleRetryDelay);
      }
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
    for (final key in const ['countries', 'sources', 'amenities', 'metro']) {
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
      setEquals(a.metro, b.metro);

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
    final radiusWasOmitted = next.centerLat == null &&
        next.centerLng == null &&
        next.radiusM == null;
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

    // The arc only means something relative to the stations it was drawn
    // against; a geography change (which _sameLocationScope already treats
    // metro selection as part of) must not keep an old direction pinned to
    // whatever station the user has since moved on from. Mirrors the radius
    // handling just above it.
    final metroChanged = !setEquals(current.metro, normalized.metro);
    final arcWasImplicitlyCarried =
        normalized.metroBearingFrom == current.metroBearingFrom &&
            normalized.metroBearingTo == current.metroBearingTo;
    final currentHasArc =
        current.metroBearingFrom != null || current.metroBearingTo != null;
    if (metroChanged && arcWasImplicitlyCarried && currentHasArc) {
      normalized = normalized.copyWith(clearMetroBearing: true);
    }
    // No stations left means no anchor for either the radius or the arc.
    if (normalized.metro.isEmpty &&
        (normalized.metroMaxM != null ||
            normalized.metroBearingFrom != null ||
            normalized.metroBearingTo != null)) {
      normalized = normalized.copyWith(
        clearMetroMaxM: true,
        clearMetroBearing: true,
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
    final sortChanged = current.sort != normalized.sort;
    filters = normalized;
    notifyListeners();
    _saveFilters(); // persist so choices survive restarts

    // The header sort control only updates the filter. Server-backed sorts need
    // a fresh cursor stream (especially price asc/desc); scheduling here also
    // makes switching back from a server sort restore the canonical feed order.
    if (sortChanged) unawaited(search());
    return true;
  }

  /// Validate a candidate custom-source URL against the backend (uses the first
  /// selected country for currency/context).
  Future<SourceValidation> validateSource(String url) {
    final country =
        filters.countries.isNotEmpty ? filters.countries.first : null;
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

  void _completePendingSearch() {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = null;
    final pending = _pendingSearchCompletion;
    _pendingSearchCompletion = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  /// Apply a short debounce to rapid filter input and actively abort any HTTP
  /// page request superseded by the new generation. The generation guard still
  /// protects state from non-cancellable test doubles and other late futures.
  Future<void> search() {
    final generation = ++_searchGeneration;
    _api.cancelListingRequests();
    _completePendingSearch();

    // A new root search supersedes any pagination/map request from the previous
    // generation. Their finally blocks intentionally no-op once stale, so clear
    // the flags here or they could remain stuck true forever.
    loadingMore = false;
    mapLoading = false;
    if (filters.countries.isEmpty) {
      listings = [];
      mapListings = [];
      nextCursor = null;
      total = 0;
      error = 'Select at least one country';
      loading = false;
      notifyListeners();
      return Future.value();
    }

    final requestedFilters = filters;
    final cacheKey = _cacheKey(requestedFilters);
    final cached = _readCache(_listingsCache, cacheKey);
    final completion = Completer<void>();
    _pendingSearchCompletion = completion;
    error = null;

    // mapListings belongs to loadMapListings' own cache (below), issued
    // separately right after this call resolves -- cleared here unconditionally,
    // same as before this cache existed, so a cache hit never leaves the
    // *previous* filter combination's markers on screen while the map's own
    // cache lookup catches up.
    mapListings = [];
    if (cached != null) {
      // Paint the held answer now -- `loading` stays false so the full-screen
      // overlay never flashes for a combination already in hand -- then
      // confirm it is still current behind the paint. The proximity filter
      // uses whatever station coordinates are already cached synchronously
      // (an async zones fetch here would defeat the instant paint); if they
      // don't cover this city yet, filtering is a no-op for this one frame
      // and self-corrects once _executeSearch's own await resolves below.
      listings = _narrowListingsByMetro(
        cached.listings,
        _metroProximityFor(requestedFilters, _metroZones),
      );
      nextCursor = cached.nextCursor;
      total = cached.total;
      degradedCountries = cached.degradedCountries;
      sourceErrors = cached.sourceErrors;
    } else {
      loading = true;
    }
    notifyListeners();

    // An answer already in hand costs the server nothing to re-apply, so it
    // also skips the debounce that exists to protect the backend from
    // combinations it has not answered yet.
    final delay = cached != null ? Duration.zero : _searchDebounce;
    _searchDebounceTimer = Timer(delay, () {
      _searchDebounceTimer = null;
      if (generation != _searchGeneration) {
        if (!completion.isCompleted) completion.complete();
        return;
      }
      unawaited(
        _executeSearch(
          generation,
          requestedFilters,
          completion,
          cacheKey: cacheKey,
          background: cached != null,
        ),
      );
    });
    return completion.future;
  }

  Future<void> _executeSearch(
    int generation,
    Filters requestedFilters,
    Completer<void> completion, {
    required String cacheKey,
    bool background = false,
  }) async {
    try {
      final res = await _api.fetchListings(requestedFilters);
      if (generation != _searchGeneration) return;
      final zones = await _zonesForMetroProximity(requestedFilters);
      if (generation != _searchGeneration) return;
      // Cache carries the server's own answer, unfiltered -- this way total
      // and nextCursor (pagination) always reflect what the server actually
      // has, and a cache hit re-applies the filter against whatever station
      // coordinates are current at that later moment rather than baking in
      // today's.
      listings = _narrowListingsByMetro(
        res.listings,
        _metroProximityFor(requestedFilters, zones),
      );
      nextCursor = res.nextCursor;
      total = res.total;
      degradedCountries = res.degradedCountries;
      sourceErrors = res.sourceErrors;
      _writeCache(_listingsCache, cacheKey, res);
      if (res.deferredMarketComparison && res.listings.isNotEmpty) {
        unawaited(_hydrateMarketComparisons(generation, res.listings));
      }
    } catch (e) {
      if (generation != _searchGeneration) return;
      // A background revalidation failure leaves the cached, already-painted
      // results on screen rather than clearing them out from under the user.
      if (!background) {
        error = e.toString();
        listings = [];
        nextCursor = null;
        total = 0;
        sourceErrors = [];
      }
    } finally {
      if (generation == _searchGeneration) {
        loading = false;
        if (identical(_pendingSearchCompletion, completion)) {
          _pendingSearchCompletion = null;
        }
        notifyListeners();
      }
      if (!completion.isCompleted) completion.complete();
    }
  }

  Future<void> _hydrateMarketComparisons(
    int generation,
    List<Listing> page,
  ) async {
    final comparisons = await _api.fetchMarketComparisons(page);
    if (generation != _searchGeneration || comparisons.isEmpty) return;

    var changed = false;
    final enriched = listings.map((item) {
      final market = comparisons[_api.marketComparisonKey(item)];
      if (market == null) return item;
      final json = item.toJson();
      json['marketComparison'] = market.toJson();
      changed = true;
      return Listing.fromJson(json);
    }).toList(growable: false);
    if (!changed || generation != _searchGeneration) return;
    listings = enriched;
    notifyListeners();
  }

  Future<void> loadMore() async {
    final cursor = nextCursor;
    if (loading || loadingMore || cursor == null || cursor.isEmpty) return;
    final generation = _searchGeneration;
    final requestedFilters = filters;
    loadingMore = true;
    notifyListeners();
    try {
      final res = await _api.fetchListings(requestedFilters, cursor: cursor);
      if (generation != _searchGeneration) return;
      final seen = listings.map(listingKey).toSet();
      final added = res.listings
          .where((item) => seen.add(listingKey(item)))
          .toList(growable: false);
      listings = [...listings, ...added];
      nextCursor = res.nextCursor;
      total = res.total;
      if (res.deferredMarketComparison && added.isNotEmpty) {
        unawaited(_hydrateMarketComparisons(generation, added));
      }
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
    final requestedFilters = filters;
    final cacheKey = _cacheKey(requestedFilters);
    final cached = _readCache(_mapCache, cacheKey);

    if (cached != null) {
      // Paint the held pins now, without the blocking overlay mapLoading
      // drives -- the fetch below still confirms them behind the paint.
      // Same synchronous-zones caveat as search()'s cache-hit path.
      mapListings = _narrowMapPointsByMetro(
        cached,
        _metroProximityFor(requestedFilters, _metroZones),
      );
    } else {
      mapLoading = true;
    }
    notifyListeners();

    try {
      final points = await _api.fetchMapListings(requestedFilters);
      if (generation != _searchGeneration) return;
      final zones = await _zonesForMetroProximity(requestedFilters);
      if (generation != _searchGeneration) return;
      mapListings = _narrowMapPointsByMetro(
        points,
        _metroProximityFor(requestedFilters, zones),
      );
      _writeCache(_mapCache, cacheKey, points);
    } catch (_) {
      // Previously an uncached failure here could throw past this method
      // (several call sites invoke it fire-and-forget, with no catch of
      // their own). Swallowing it and leaving whatever pins were already on
      // screen -- cached or from the last successful fetch -- is strictly
      // better than an unhandled exception surfacing from a secondary feed;
      // the mirrored web map applies the same rule to its own fetch.
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
    _api.cancelListingRequests();
    _completePendingSearch();
    final generation = ++_searchGeneration;
    loadingMore = false;
    mapLoading = false;
    mapListings = [];
    loading = true;
    error = null;
    notifyListeners();
    final requestedFilters = filters;
    try {
      final res = await _api.fetchListings(requestedFilters, force: true);
      if (generation != _searchGeneration) return;
      listings = res.listings;
      nextCursor = res.nextCursor;
      total = res.total;
      degradedCountries = res.degradedCountries;
      sourceErrors = res.sourceErrors;
      // A forced scrape is the freshest possible answer for this exact filter
      // combination -- update the cache so a plain search() back to it, right
      // after, does not serve what reloadAll just deliberately bypassed.
      _writeCache(_listingsCache, _cacheKey(requestedFilters), res);
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

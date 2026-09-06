export 'api_service_base.dart' hide ApiService;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/filters.dart';
import '../models/listing.dart';
import '../models/map_listing_point.dart';
import 'api_service_base.dart' as base;

/// Public transport facade.
///
/// Geographic result membership belongs to the backend/database. The legacy
/// transport implementation still calls `Filters.toUpstreamQueryParams()`,
/// which intentionally used to strip multi-station metro filters and the
/// directional arc so Flutter could post-filter a returned page. Wrap the
/// request filter here so every selected station, radius and arc is sent to the
/// backend while the rest of the mature transport/cache implementation remains
/// unchanged.
///
/// The facade also owns the small amount of cross-request policy that must be
/// consistent application-wide: startup prefetch, metadata deadlines and
/// validation of externally launchable listing URLs.
class ApiService extends base.ApiService {
  ApiService({String? baseUrl}) : super(baseUrl: baseUrl);

  static const _filtersPreferenceKey = 'filters';
  static const _countriesCacheKey = 'api.countries.cache.v1';
  static const _metadataTimeout = Duration(seconds: 12);

  Future<base.ListingsResult>? _startupPrefetch;
  String? _startupPrefetchKey;
  bool _startupPrefetchAttempted = false;

  /// On a cold start AppState restores filters, then used to wait for countries
  /// before it even started the first listing request. Start that independent
  /// request while countries are in flight and hold the result for the first
  /// matching fetchListings call. Critical-path latency becomes roughly
  /// max(countries, listings) instead of countries + listings.
  ///
  /// Once a country catalog has been fetched successfully, subsequent launches
  /// use the stored copy immediately and refresh it in the background. That
  /// takes countries off the critical path entirely after the first launch.
  @override
  Future<List<Country>> fetchCountries({String locale = ''}) async {
    if (locale.isNotEmpty || _startupPrefetchAttempted) {
      return super
          .fetchCountries(locale: locale)
          .timeout(_metadataTimeout);
    }

    _startupPrefetchAttempted = true;
    final prefetch = _prefetchStartupListings();
    final cached = await _readCachedCountries();
    if (cached.isNotEmpty) {
      unawaited(_refreshCountriesCache());
      // AppState calls cancelListingRequests() at the start of search(). Wait
      // for the startup request to settle before returning cached metadata so
      // that normal cancellation cannot kill the useful prefetched page.
      await prefetch;
      return cached;
    }

    final countries = await super
        .fetchCountries(locale: locale)
        .timeout(_metadataTimeout);
    await _writeCachedCountries(countries);
    await prefetch;
    return countries;
  }

  Future<void> _refreshCountriesCache() async {
    try {
      final countries = await super
          .fetchCountries()
          .timeout(_metadataTimeout);
      await _writeCachedCountries(countries);
    } catch (_) {
      // Stale metadata is still enough to render filters while the normal
      // localized fetch can retry later; a background refresh never blocks feed.
    }
  }

  Future<List<Country>> _readCachedCountries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_countriesCacheKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => Country.fromJson(Map<String, dynamic>.from(item)))
          .where((country) => country.code.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeCachedCountries(List<Country> countries) async {
    if (countries.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _countriesCacheKey,
        jsonEncode(countries.map(_countryToJson).toList(growable: false)),
      );
    } catch (_) {}
  }

  Map<String, dynamic> _countryToJson(Country country) => {
        'code': country.code,
        'name': country.name,
        'currency': country.currency,
        'callingCode': country.callingCode,
        'center': {'lat': country.centerLat, 'lng': country.centerLng},
        'cities': country.cities,
        'cityLabels': country.cityLabels,
        'locations': country.locations.map(
          (city, locations) => MapEntry(city, {
            'districts': locations.districts,
            'metro': locations.metro,
            'microdistricts': locations.microdistricts,
            'quartals': locations.quartals,
            'areas': locations.areas,
            'districtLabels': locations.districtLabels,
            'metroLabels': locations.metroLabels,
            'microdistrictLabels': locations.microdistrictLabels,
            'quartalLabels': locations.quartalLabels,
            'areaLabels': locations.areaLabels,
          }),
        ),
      };

  Future<void> _prefetchStartupListings() async {
    try {
      var filters = Filters();
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_filtersPreferenceKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          filters = Filters.fromJson(Map<String, dynamic>.from(decoded));
        }
      }

      _startupPrefetchKey = _requestKey(filters);
      final request = super.fetchListings(_BackendOwnedGeoFilters(filters));
      _startupPrefetch = request;
      await request;
    } catch (_) {
      // Prefetch is an optimisation only. The normal request path below still
      // gets a clean attempt and owns any user-visible error state.
      _startupPrefetch = null;
      _startupPrefetchKey = null;
    }
  }

  String _requestKey(Filters filters) {
    final payload = Map<String, dynamic>.from(filters.toJson());
    for (final key in const ['countries', 'sources', 'amenities', 'metro']) {
      final values = (payload[key] as List? ?? const [])
          .map((item) => item.toString())
          .toList()
        ..sort();
      payload[key] = values;
    }
    return jsonEncode(payload);
  }

  @override
  Future<base.ListingsResult> fetchListings(
    Filters filters, {
    bool force = false,
    String? cursor,
  }) async {
    if (!force && cursor == null && _startupPrefetch != null) {
      final key = _requestKey(filters);
      if (key == _startupPrefetchKey) {
        final prefetched = _startupPrefetch!;
        _startupPrefetch = null;
        _startupPrefetchKey = null;
        return _sanitizeResult(await prefetched);
      }
      // The user/filter state changed before the initial request was consumed.
      // The completed value is not useful for this cursor stream.
      _startupPrefetch = null;
      _startupPrefetchKey = null;
    }

    final result = await super.fetchListings(
      _BackendOwnedGeoFilters(filters),
      force: force,
      cursor: cursor,
    );
    return _sanitizeResult(result);
  }

  @override
  Future<List<MapListingPoint>> fetchMapListings(Filters filters) =>
      super.fetchMapListings(_BackendOwnedGeoFilters(filters));

  @override
  Future<Listing?> reloadListing(Listing listing) async {
    final fresh = await super.reloadListing(listing);
    return fresh == null ? null : _sanitizeListing(fresh);
  }

  @override
  Future<Listing?> fetchListingByPublicId(int publicId) async {
    final listing = await super.fetchListingByPublicId(publicId);
    return listing == null ? null : _sanitizeListing(listing);
  }

  @override
  Future<Map<String, double>> fetchRates() =>
      super.fetchRates().timeout(_metadataTimeout);

  /// Poll translation jobs with bounded exponential backoff instead of a fixed
  /// 2-second interval. A five-minute job now performs roughly a few dozen
  /// status requests rather than up to ~150, reducing radio wakeups/backend
  /// load while still checking quickly during the first seconds of inference.
  @override
  Future<String> translateText(
    String text, {
    required String targetLanguage,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty) return '';

    var job = await _startTranslation(normalized, targetLanguage);
    if (job.status == 'completed' &&
        job.translatedText?.trim().isNotEmpty == true) {
      return job.translatedText!.trim();
    }
    if (job.status == 'disabled') throw Exception('translation disabled');
    if (job.status == 'failed') {
      throw Exception(job.error ?? 'translation failed');
    }
    final key = job.key;
    if (key == null || key.isEmpty) throw Exception('translation key missing');

    final deadline = DateTime.now().add(timeout);
    var consecutivePollErrors = 0;
    var delay = const Duration(seconds: 1);
    const maxDelay = Duration(seconds: 10);

    while (DateTime.now().isBefore(deadline)) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      await Future<void>.delayed(delay < remaining ? delay : remaining);

      try {
        job = await _translationResult(key);
        consecutivePollErrors = 0;
      } catch (_) {
        consecutivePollErrors += 1;
        if (consecutivePollErrors >= 5) rethrow;
        delay = _nextTranslationPollDelay(delay, maxDelay);
        continue;
      }

      if (job.status == 'completed') {
        final translated = job.translatedText?.trim() ?? '';
        if (translated.isEmpty) throw Exception('translation was empty');
        return translated;
      }
      if (job.status == 'failed' ||
          job.status == 'not_found' ||
          job.status == 'disabled') {
        throw Exception(job.error ?? 'translation ${job.status}');
      }
      delay = _nextTranslationPollDelay(delay, maxDelay);
    }

    throw TimeoutException(
      'translation did not finish before the client deadline',
    );
  }

  Duration _nextTranslationPollDelay(Duration current, Duration max) {
    final doubled = current.inMilliseconds * 2;
    return Duration(
      milliseconds: doubled > max.inMilliseconds ? max.inMilliseconds : doubled,
    );
  }

  Future<base.TranslationJob> _startTranslation(
    String text,
    String targetLanguage,
  ) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/api/translation'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'text': text, 'targetLanguage': targetLanguage}),
        )
        .timeout(const Duration(seconds: 15));
    final decoded = jsonDecode(res.body);
    if (decoded is! Map) throw const FormatException('translation response');
    final json = Map<String, dynamic>.from(decoded);
    if (res.statusCode != 200) {
      throw Exception(
        json['error']?.toString() ?? 'translation HTTP ${res.statusCode}',
      );
    }
    return base.TranslationJob.fromJson(json);
  }

  Future<base.TranslationJob> _translationResult(String key) async {
    final res = await http
        .get(Uri.parse('$baseUrl/api/translation/$key'))
        .timeout(const Duration(seconds: 15));
    final decoded = jsonDecode(res.body);
    if (decoded is! Map) throw const FormatException('translation response');
    final json = Map<String, dynamic>.from(decoded);
    if (res.statusCode != 200) {
      throw Exception(
        json['error']?.toString() ?? 'translation HTTP ${res.statusCode}',
      );
    }
    return base.TranslationJob.fromJson(json);
  }

  base.ListingsResult _sanitizeResult(base.ListingsResult result) =>
      base.ListingsResult(
        result.listings.map(_sanitizeListing).toList(growable: false),
        result.degradedCountries,
        result.sourceErrors,
        nextCursor: result.nextCursor,
        total: result.total,
        deferredMarketComparison: result.deferredMarketComparison,
      );

  Listing _sanitizeListing(Listing listing) {
    final safeUrl = safeExternalListingUrl(listing.url);
    if (safeUrl == listing.url) return listing;
    final json = listing.toJson();
    json['url'] = safeUrl;
    return Listing.fromJson(json);
  }
}

/// Scraped URLs are data, not trusted navigation instructions. Only ordinary
/// web links are allowed to leave the app; custom schemes such as intent:, file:
/// or javascript: are rejected at the transport boundary before UI sees them.
String safeExternalListingUrl(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';
  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) return '';
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'https' && scheme != 'http') return '';
  return uri.toString();
}

/// Minimal request proxy: ApiService only reads query/customSources/sort from
/// the filter object outside serialization. The actual query parameter map is
/// delegated to the original filter's complete deep-link serializer, which now
/// doubles as the canonical backend contract for geo filters.
class _BackendOwnedGeoFilters extends Filters {
  _BackendOwnedGeoFilters(this.source)
      : super(
          query: source.query,
          customSources: source.customSources,
          sort: source.sort,
        );

  final Filters source;

  @override
  Map<String, String> toUpstreamQueryParams() => source.toQueryParams();
}

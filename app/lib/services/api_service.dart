export 'api_service_base.dart' hide ApiService;

import 'dart:convert';

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
  static const _metadataTimeout = Duration(seconds: 12);

  Future<base.ListingsResult>? _startupPrefetch;
  String? _startupPrefetchKey;
  bool _startupPrefetchAttempted = false;

  /// On a cold start AppState restores filters, then used to wait for countries
  /// before it even started the first listing request. Start that independent
  /// request while countries are in flight and hold the result for the first
  /// matching fetchListings call. Critical-path latency becomes roughly
  /// max(countries, listings) instead of countries + listings.
  @override
  Future<List<Country>> fetchCountries({String locale = ''}) async {
    if (locale.isNotEmpty || _startupPrefetchAttempted) {
      return super
          .fetchCountries(locale: locale)
          .timeout(_metadataTimeout);
    }

    _startupPrefetchAttempted = true;
    final prefetch = _prefetchStartupListings();
    final countries = await super
        .fetchCountries(locale: locale)
        .timeout(_metadataTimeout);
    // Do not hand control back to AppState until the prefetched request has
    // settled. Its subsequent search() calls cancelListingRequests(); waiting
    // here prevents that normal cancellation from killing useful startup work.
    await prefetch;
    return countries;
  }

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

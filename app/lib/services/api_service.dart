import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/district_zone.dart';
import '../models/filters.dart';
import '../models/listing.dart';
import '../models/search_statistics.dart';

/// A source that failed during a search (a built-in scraper or a custom URL).
class SourceError {
  final String source; // olx | telegram | custom | ...
  final String? url; // set for custom sources
  final String message;
  SourceError({required this.source, this.url, required this.message});

  factory SourceError.fromJson(Map<String, dynamic> j) => SourceError(
        source: (j['source'] ?? 'source').toString(),
        url: j['url']?.toString(),
        message: (j['error'] ?? 'Failed').toString(),
      );
}

class ListingsResult {
  final List<Listing> listings;
  final List<String> degradedCountries; // served from demo data right now
  final List<SourceError> sourceErrors; // per-source failures to surface
  final String? nextCursor;
  final int total;
  ListingsResult(
    this.listings,
    this.degradedCountries,
    this.sourceErrors, {
    this.nextCursor,
    this.total = 0,
  });
}

/// Thrown when the backend rejects a manual reload with HTTP 429 (flood
/// protection). Carries the suggested wait so the UI can tell the user.
class RateLimitException implements Exception {
  final int retryAfterMs;
  RateLimitException(this.retryAfterMs);
}

/// Outcome of validating a candidate custom-source URL.
class SourceValidation {
  final bool ok;
  final int count;
  final String? error;
  SourceValidation({required this.ok, required this.count, this.error});
}

/// Snapshot returned by the asynchronous translation endpoints.
class TranslationJob {
  final String status;
  final String? key;
  final String? translatedText;
  final String? sourceLanguage;
  final String? error;

  const TranslationJob({
    required this.status,
    this.key,
    this.translatedText,
    this.sourceLanguage,
    this.error,
  });

  factory TranslationJob.fromJson(Map<String, dynamic> j) {
    final data = j['data'] is Map<String, dynamic>
        ? j['data'] as Map<String, dynamic>
        : <String, dynamic>{};
    return TranslationJob(
      status: (j['status'] ?? 'failed').toString(),
      key: j['key']?.toString(),
      translatedText: data['translatedText']?.toString(),
      sourceLanguage: data['sourceLanguage']?.toString(),
      error: j['error']?.toString(),
    );
  }
}

class ApiService {
  ApiService({String? baseUrl}) : baseUrl = baseUrl ?? _defaultBaseUrl();

  final String baseUrl;

  /// Production backend, reachable from a real device — proxied through
  /// whiteslove.me's existing HTTPS vhost (nginx `location /flat-api/` ->
  /// 127.0.0.1:4000) rather than the bare http://185.5.206.229:8082 this
  /// used to point at. Plain HTTP on a non-standard port gets silently
  /// dropped by some mobile carriers (a real device hung on a 30s timeout
  /// with no error while this exact IP:port answered fine from a desktop
  /// browser); 443 over TLS on an existing domain is essentially never
  /// blocked. Only debug builds default to a local backend instead (the
  /// Android emulator reaches the host machine via 10.0.2.2; desktop/web
  /// use localhost), since a release APK installed on a phone has no "host
  /// machine" to reach.
  /// Override with --dart-define=API_BASE=http://your-host:4000.
  static const String kProductionBaseUrl = 'https://whiteslove.me/flat-api';

  static String _defaultBaseUrl() {
    const override = String.fromEnvironment('API_BASE');
    if (override.isNotEmpty) return override;
    if (kReleaseMode) return kProductionBaseUrl;
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:4000';
    return 'http://localhost:4000';
  }

  /// Telegram photos come back as backend-relative paths ("/api/tg-photo/…")
  /// since the image is proxied through our server; make them absolute so the
  /// image widgets can load them. Absolute URLs (OLX CDN etc.) pass through.
  String _resolvePhoto(Object? raw) {
    final s = raw?.toString() ?? '';
    return s.startsWith('/') ? '$baseUrl$s' : s;
  }

  Map<String, dynamic> _absolutizePhotos(Map<String, dynamic> j) {
    if (j['photo'] != null) j['photo'] = _resolvePhoto(j['photo']);
    if (j['photos'] is List) {
      j['photos'] = (j['photos'] as List).map(_resolvePhoto).toList();
    }
    return j;
  }

  /// [locale] asks the backend to also return localized display labels
  /// (`cityLabels`, `districtLabels`, etc. on each Country/CityLocations) via
  /// parsing-lexicon's own geography translation table — the same one the
  /// website uses. Pass '' (or omit) to skip that extra work server-side
  /// when only the raw names are needed.
  Future<List<Country>> fetchCountries({String locale = ''}) async {
    final uri = Uri.parse('$baseUrl/api/countries')
        .replace(queryParameters: locale.isEmpty ? null : {'locale': locale});
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('countries HTTP ${res.statusCode}');
    }
    final list = jsonDecode(res.body) as List;
    return list.map((e) => Country.fromJson(e)).toList();
  }

  /// Parse the server's suggested wait (from body or the Retry-After header),
  /// defaulting to a few seconds if absent.
  int _retryAfterMs(http.Response res) {
    try {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final ms = (j['retryAfterMs'] as num?)?.toInt();
      if (ms != null && ms > 0) return ms;
    } catch (_) {}
    final hdr = int.tryParse(res.headers['retry-after'] ?? '');
    return hdr != null ? hdr * 1000 : 3000;
  }

  /// [force] triggers a fresh backend scrape (bypasses the cache) — used by the
  /// manual "Reload all" action. It is flood-protected server-side (429).
  Future<ListingsResult> fetchListings(
    Filters filters, {
    bool force = false,
    String? cursor,
  }) async {
    final params = Map<String, String>.from(filters.toQueryParams());
    if (force) params['refresh'] = '1';
    if (cursor != null && cursor.isNotEmpty) params['cursor'] = cursor;
    final uri =
        Uri.parse('$baseUrl/api/listings').replace(queryParameters: params);
    final res = await http.get(uri).timeout(const Duration(seconds: 30));
    if (res.statusCode == 429) throw RateLimitException(_retryAfterMs(res));
    if (res.statusCode != 200) {
      throw Exception('listings HTTP ${res.statusCode}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final listings = (json['listings'] as List)
        .map(
          (e) => Listing.fromJson(_absolutizePhotos(e as Map<String, dynamic>)),
        )
        .toList();
    final degraded = (json['degradedCountries'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    final errors = (json['sourceErrors'] as List? ?? [])
        .map((e) => SourceError.fromJson(e as Map<String, dynamic>))
        .toList();
    return ListingsResult(
      listings,
      degraded,
      errors,
      nextCursor: json['nextCursor']?.toString(),
      total: (json['count'] as num?)?.toInt() ?? listings.length,
    );
  }

  /// Compact full-map feed. The backend walks every result cursor internally,
  /// so Flutter shows the same flats as the web map instead of one card page.
  Future<List<Listing>> fetchMapListings(Filters filters) async {
    final params = Map<String, String>.from(filters.toQueryParams())
      ..['mapOnly'] = 'true';
    final uri =
        Uri.parse('$baseUrl/api/listings').replace(queryParameters: params);
    final res = await http.get(uri).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) return const [];
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return ((json['mapPoints'] as List?) ?? const [])
        .map((point) => Listing.fromJson(point as Map<String, dynamic>))
        .toList();
  }

  /// Re-fetch a single listing fresh from its source (manual "Reload this
  /// listing"). Returns the updated listing, or null if it's gone. Throws
  /// [RateLimitException] on 429.
  Future<Listing?> reloadListing(Listing l) async {
    final uri = Uri.parse('$baseUrl/api/listing/${l.source}/${l.id}')
        .replace(queryParameters: {'country': l.country});
    final res = await http.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode == 429) throw RateLimitException(_retryAfterMs(res));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw Exception('reload HTTP ${res.statusCode}');
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final j = json['listing'];
    if (j == null) return null;
    return Listing.fromJson(_absolutizePhotos(j as Map<String, dynamic>));
  }

  /// Look up a listing by its stable [publicId] (the `#12345` shown in the
  /// detail title / used for single-listing share links) rather than its
  /// source+id pair. Returns null if it's gone or the id doesn't exist —
  /// callers that expect a freshly-scraped listing may need to retry for a
  /// few seconds while it's indexed, same as the site's polling fallback.
  Future<Listing?> fetchListingByPublicId(int publicId) async {
    final uri = Uri.parse('$baseUrl/api/listing/by-public-id/$publicId');
    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return null;
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final j = json['listing'];
    if (j == null) return null;
    return Listing.fromJson(_absolutizePhotos(j as Map<String, dynamic>));
  }

  /// Ask the backend to fetch and validate a custom-source URL before the user
  /// commits to adding it. Returns how many listings it could read, or an error.
  Future<SourceValidation> validateSource(String url, {String? country}) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/sources/validate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'url': url,
              if (country != null) 'country': country,
            }),
          )
          .timeout(const Duration(seconds: 20));
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      return SourceValidation(
        ok: json['ok'] == true,
        count: (json['count'] as num?)?.toInt() ?? 0,
        error: json['error']?.toString(),
      );
    } catch (e) {
      return SourceValidation(
        ok: false,
        count: 0,
        error: 'Could not reach server',
      );
    }
  }

  Future<TranslationJob> _startTranslation(
    String text,
    String targetLanguage,
  ) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/api/translation'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'text': text, 'targetLanguage': targetLanguage}),
        )
        .timeout(const Duration(seconds: 15));
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(
        json['error']?.toString() ?? 'translation HTTP ${res.statusCode}',
      );
    }
    return TranslationJob.fromJson(json);
  }

  Future<TranslationJob> _translationResult(String key) async {
    final res = await http
        .get(Uri.parse('$baseUrl/api/translation/$key'))
        .timeout(const Duration(seconds: 15));
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(
        json['error']?.toString() ?? 'translation HTTP ${res.statusCode}',
      );
    }
    return TranslationJob.fromJson(json);
  }

  /// Translate listing text without holding one HTTP request open while Ollama
  /// works. Submission returns a key immediately and this method polls the
  /// cached BullMQ result. The overall deadline intentionally exceeds the
  /// worker's 180-second translation inference budget and leaves room for queue
  /// wait behind one already-running CPU job.
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
    if (job.status == 'failed')
      throw Exception(job.error ?? 'translation failed');
    final key = job.key;
    if (key == null || key.isEmpty) throw Exception('translation key missing');

    final deadline = DateTime.now().add(timeout);
    var consecutivePollErrors = 0;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        job = await _translationResult(key);
        consecutivePollErrors = 0;
      } catch (_) {
        // A short backend/worker hiccup must not discard an already-running AI
        // job. Retry polling, but fail after several consecutive transport errors.
        consecutivePollErrors += 1;
        if (consecutivePollErrors >= 5) rethrow;
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
    }

    throw TimeoutException(
      'translation did not finish before the client deadline',
    );
  }

  /// Exchange rates relative to USD (units of currency per 1 USD), used to
  /// convert listing prices into the user's chosen display currency.
  /// Aggregate statistics for the current filters (deal-type breakdown,
  /// median prices, ownership split, top geographies) without paying for a
  /// page of listings — `statsOnly` skips the row fetch server-side.
  Future<SearchStatistics?> fetchSearchStatistics(Filters filters) async {
    final params = Map<String, String>.from(filters.toQueryParams());
    params['includeStats'] = 'true';
    params['statsOnly'] = 'true';
    final uri =
        Uri.parse('$baseUrl/api/listings').replace(queryParameters: params);
    final res = await http.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return null;
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final stats = json['statistics'];
    if (stats == null) return null;
    return SearchStatistics.fromJson(stats as Map<String, dynamic>);
  }

  /// All map colour-zone layers (districts, microdistricts, quartals/
  /// mahallas, areas), same palette/boundaries as the site's map. Empty
  /// zones when the backend has no data for this country/city rather than
  /// throwing, so callers can just skip the overlay.
  Future<MapZones> fetchMapZones(
    String country,
    String city, {
    String locale = '',
  }) async {
    if (country.isEmpty || city.isEmpty) return const MapZones();
    final uri = Uri.parse('$baseUrl/api/district-zones').replace(
      queryParameters: {
        'country': country,
        'city': city,
        if (locale.isNotEmpty) 'locale': locale,
      },
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return const MapZones();
    return MapZones.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<Map<String, double>> fetchRates() async {
    final res = await http.get(Uri.parse('$baseUrl/api/rates'));
    if (res.statusCode != 200) {
      throw Exception('rates HTTP ${res.statusCode}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final rates = (json['rates'] as Map<String, dynamic>? ?? {});
    return rates.map((k, v) => MapEntry(k, (v as num).toDouble()));
  }
}

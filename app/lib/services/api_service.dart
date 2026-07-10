import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/filters.dart';
import '../models/listing.dart';

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
  ListingsResult(this.listings, this.degradedCountries, this.sourceErrors);
}

/// Outcome of validating a candidate custom-source URL.
class SourceValidation {
  final bool ok;
  final int count;
  final String? error;
  SourceValidation({required this.ok, required this.count, this.error});
}

class ApiService {
  ApiService({String? baseUrl}) : baseUrl = baseUrl ?? _defaultBaseUrl();

  final String baseUrl;

  /// The Android emulator reaches the host machine via 10.0.2.2; desktop/web
  /// use localhost. Override with --dart-define=API_BASE=http://your-host:4000.
  static String _defaultBaseUrl() {
    const override = String.fromEnvironment('API_BASE');
    if (override.isNotEmpty) return override;
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:4000';
    return 'http://localhost:4000';
  }

  Future<List<Country>> fetchCountries() async {
    final res = await http.get(Uri.parse('$baseUrl/api/countries'));
    if (res.statusCode != 200) {
      throw Exception('countries HTTP ${res.statusCode}');
    }
    final list = jsonDecode(res.body) as List;
    return list.map((e) => Country.fromJson(e)).toList();
  }

  Future<ListingsResult> fetchListings(Filters filters) async {
    final uri = Uri.parse('$baseUrl/api/listings')
        .replace(queryParameters: filters.toQueryParams());
    final res = await http.get(uri).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('listings HTTP ${res.statusCode}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final listings = (json['listings'] as List)
        .map((e) => Listing.fromJson(e as Map<String, dynamic>))
        .toList();
    final degraded =
        (json['degradedCountries'] as List? ?? []).map((e) => e.toString()).toList();
    final errors = (json['sourceErrors'] as List? ?? [])
        .map((e) => SourceError.fromJson(e as Map<String, dynamic>))
        .toList();
    return ListingsResult(listings, degraded, errors);
  }

  /// Ask the backend to fetch and validate a custom-source URL before the user
  /// commits to adding it. Returns how many listings it could read, or an error.
  Future<SourceValidation> validateSource(String url, {String? country}) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/sources/validate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'url': url, if (country != null) 'country': country}),
          )
          .timeout(const Duration(seconds: 20));
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      return SourceValidation(
        ok: json['ok'] == true,
        count: (json['count'] as num?)?.toInt() ?? 0,
        error: json['error']?.toString(),
      );
    } catch (e) {
      return SourceValidation(ok: false, count: 0, error: 'Could not reach server');
    }
  }

  /// Exchange rates relative to USD (units of currency per 1 USD), used to
  /// convert listing prices into the user's chosen display currency.
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

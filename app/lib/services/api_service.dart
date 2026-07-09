import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/filters.dart';
import '../models/listing.dart';

class ListingsResult {
  final List<Listing> listings;
  final List<String> degradedCountries; // served from demo data right now
  ListingsResult(this.listings, this.degradedCountries);
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
    return ListingsResult(listings, degraded);
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

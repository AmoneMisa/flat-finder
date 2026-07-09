import 'package:flutter/foundation.dart';

import '../models/filters.dart';
import '../models/listing.dart';
import '../services/api_service.dart';

class AppState extends ChangeNotifier {
  AppState(this._api);

  final ApiService _api;

  List<Country> countries = [];
  Filters filters = Filters();
  List<Listing> listings = [];
  List<String> degradedCountries = [];
  Map<String, double> rates = {}; // currency -> units per 1 USD

  bool loading = false;
  String? error;

  Future<void> init() async {
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

  Country? countryByCode(String code) {
    for (final c in countries) {
      if (c.code == code) return c;
    }
    return null;
  }

  void updateFilters(Filters next) {
    filters = next;
    notifyListeners();
  }

  Future<void> search() async {
    if (filters.countries.isEmpty) {
      listings = [];
      error = 'Select at least one country';
      notifyListeners();
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      final res = await _api.fetchListings(filters);
      listings = res.listings;
      degradedCountries = res.degradedCountries;
    } catch (e) {
      error = e.toString();
      listings = [];
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

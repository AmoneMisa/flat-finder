import 'dart:math' as math;

import '../l10n/strings.dart';
import '../models/filters.dart';
import '../models/listing.dart';

/// Shared with the filter sheet's sort dropdown and the quick-access sort
/// control on the main screen, so both stay in sync automatically.
String sortLabel(AppStrings s, SortBy v) => switch (v) {
      SortBy.relevance => s.t('sortRelevance'),
      SortBy.dateNew => s.t('sortDate'),
      SortBy.dateOld => s.t('sortDateOld'),
      SortBy.priceAsc => s.t('sortPriceAsc'),
      SortBy.priceDesc => s.t('sortPriceDesc'),
      SortBy.areaDesc => s.t('sortArea'),
      SortBy.distanceCenter => s.t('sortCenter'),
      SortBy.distanceMetro => s.t('sortMetro'),
    };

/// Great-circle distance in km between two lat/lng points (haversine).
double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0; // Earth radius, km
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Price expressed in [displayCurrency] (or native) for comparison, or null.
num? _comparablePrice(
  Listing l,
  Map<String, double>? rates,
  String? displayCurrency,
) {
  if (l.price == null) return null;
  final from = rates?[l.currency];
  final to = displayCurrency == null ? null : rates?[displayCurrency];
  if (displayCurrency != null &&
      displayCurrency != l.currency &&
      from != null &&
      to != null &&
      from > 0) {
    return l.price! * to / from;
  }
  return l.price;
}

/// Returns a new list ordered per [sort]. Listings with an unknown sort key are
/// pushed to the end so the meaningful ones stay on top. [centerLat]/[centerLng]
/// are the selected country's center, used for the distance sorts.
List<Listing> sortListings(
  List<Listing> listings,
  SortBy sort, {
  double? centerLat,
  double? centerLng,
  Map<String, double>? rates,
  String? displayCurrency,
}) {
  if (sort == SortBy.relevance) return listings;
  final out = [...listings];

  // Comparator that always sends "unknown" (null) keys to the bottom.
  int byNum(num? a, num? b, {bool asc = true}) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return asc ? a.compareTo(b) : b.compareTo(a);
  }

  switch (sort) {
    case SortBy.dateNew:
      out.sort((a, b) {
        final da = a.createdAt, db = b.createdAt;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da); // newest first
      });
    case SortBy.dateOld:
      out.sort((a, b) {
        final da = a.createdAt, db = b.createdAt;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      });
    case SortBy.priceAsc:
      out.sort(
        (a, b) => byNum(
          _comparablePrice(a, rates, displayCurrency),
          _comparablePrice(b, rates, displayCurrency),
        ),
      );
    case SortBy.priceDesc:
      out.sort(
        (a, b) => byNum(
          _comparablePrice(a, rates, displayCurrency),
          _comparablePrice(b, rates, displayCurrency),
          asc: false,
        ),
      );
    case SortBy.areaDesc:
      out.sort((a, b) => byNum(a.areaSqm, b.areaSqm, asc: false));
    case SortBy.distanceCenter:
      if (centerLat == null || centerLng == null) return listings;
      num? d(Listing l) => l.hasLocation
          ? _distanceKm(l.lat!, l.lng!, centerLat, centerLng)
          : null;
      out.sort((a, b) => byNum(d(a), d(b)));
    case SortBy.distanceMetro:
      // No station coordinates are available, so this is best-effort: listings
      // that name a nearby metro come first (closest to transit), the rest by
      // distance from the city center.
      out.sort((a, b) {
        final am = a.metro != null, bm = b.metro != null;
        if (am != bm) return am ? -1 : 1;
        if (centerLat == null || centerLng == null) return 0;
        num? d(Listing l) => l.hasLocation
            ? _distanceKm(l.lat!, l.lng!, centerLat, centerLng)
            : null;
        return byNum(d(a), d(b));
      });
    case SortBy.relevance:
      break;
  }
  return out;
}

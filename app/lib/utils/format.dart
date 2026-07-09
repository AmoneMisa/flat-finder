import 'package:intl/intl.dart';

import '../l10n/strings.dart';
import '../models/listing.dart';

/// Formats a listing's price, optionally converting it into [displayCurrency]
/// using [rates] (units of currency per 1 USD, as returned by /api/rates).
/// Falls back to the listing's native currency when conversion isn't possible.
String formatPrice(
  Listing l, {
  Map<String, double>? rates,
  String? displayCurrency,
  AppStrings? s,
}) {
  if (l.price == null) return s?.t('priceOnRequest') ?? 'Price on request';

  num price = l.price!;
  String currency = l.currency;

  final from = rates?[l.currency];
  final to = displayCurrency == null ? null : rates?[displayCurrency];
  if (displayCurrency != null &&
      displayCurrency != l.currency &&
      from != null &&
      to != null &&
      from > 0) {
    price = price * to / from;
    currency = displayCurrency;
  }

  final f = NumberFormat.decimalPattern();
  return '${f.format(price.round())} $currency';
}

String propertyLabel(String type, [AppStrings? s]) =>
    type == 'house' ? (s?.t('house') ?? 'House') : (s?.t('apartment') ?? 'Apartment');

String subtitleFor(Listing l, [AppStrings? s]) {
  final parts = <String>[];
  if (l.rooms != null) {
    parts.add(s?.t('roomsN', {'n': '${l.rooms}'}) ?? '${l.rooms} rooms');
  }
  if (l.areaSqm != null) parts.add('${l.areaSqm} m²');
  final floor = floorLabel(l, s);
  if (floor != null) parts.add(floor);
  // Prefer the more specific "City, District" when we have a district.
  if (l.city.isNotEmpty && l.district != null) {
    parts.add('${l.city}, ${l.district}');
  } else if (l.city.isNotEmpty) {
    parts.add(l.city);
  }
  return parts.join(' · ');
}

/// "Floor 5/9" / "Floor 5", or null when unknown.
String? floorLabel(Listing l, [AppStrings? s]) {
  if (l.floor == null) return null;
  if (l.totalFloors != null) {
    return s?.t('floorOf', {'n': '${l.floor}', 'total': '${l.totalFloors}'}) ??
        'Floor ${l.floor}/${l.totalFloors}';
  }
  return s?.t('floorN', {'n': '${l.floor}'}) ?? 'Floor ${l.floor}';
}

/// Human label for a listing's stated tenant restriction, or null.
String? audienceLabel(String? audience, [AppStrings? s]) => switch (audience) {
      'women' => s?.t('women') ?? 'Girls only',
      'men' => s?.t('men') ?? 'Men only',
      'family' => s?.t('family') ?? 'Family',
      _ => null,
    };

const countryFlags = {
  'RO': '🇷🇴',
  'UA': '🇺🇦',
  'KZ': '🇰🇿',
  'UZ': '🇺🇿',
};

String sourceLabel(String source, [AppStrings? s]) => switch (source) {
      'olx' => 'OLX',
      'reddit' => 'Reddit',
      'telegram' => 'Telegram',
      'threads' => 'Threads',
      'mock' => s?.t('demo') ?? 'Demo',
      _ => source,
    };

/// Short human label for a listing's deal type, or null when unknown.
String? dealTypeLabel(String? dealType, [AppStrings? s]) => switch (dealType) {
      'sale' => s?.t('saleLong') ?? 'Sale',
      'longRent' => s?.t('longRentLong') ?? 'Long-term rent',
      'shortRent' => s?.t('shortRentLong') ?? 'Short-term rent',
      _ => null,
    };

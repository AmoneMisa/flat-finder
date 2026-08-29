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

  final f = NumberFormat.decimalPattern();
  final native = '${f.format(l.price!.round())} ${l.currency}'.trim();

  final from = rates?[l.currency];
  final to = displayCurrency == null ? null : rates?[displayCurrency];
  final canConvert =
      displayCurrency != null &&
      displayCurrency != l.currency &&
      from != null &&
      to != null &&
      from > 0;
  if (!canConvert) return native;

  // Show the converted amount, with the original in parentheses for reference.
  final converted = l.price! * to / from;
  return '${f.format(converted.round())} $displayCurrency ($native)';
}

/// Short currency symbol for a code, falling back to the code itself
/// (e.g. UZS/KZT have no widely-recognised single glyph).
String currencySymbol(String code) => switch (code.toUpperCase()) {
  'USD' => '\$',
  'EUR' => '€',
  'UAH' => '₴',
  'RON' => 'lei',
  'RUB' => '₽',
  'GBP' => '£',
  _ => code,
};

/// Compact price for a map pin: converts into [displayCurrency] when possible,
/// then renders "<symbol><short number>" (e.g. "$45K", "1.2M сум"). Returns "—"
/// when the price is unknown.
String pinPriceLabel(
  Listing l, {
  Map<String, double>? rates,
  String? displayCurrency,
}) {
  if (l.price == null) return '—';
  var value = l.price!;
  var code = l.currency;
  final from = rates?[l.currency];
  final to = displayCurrency == null ? null : rates?[displayCurrency];
  if (displayCurrency != null &&
      displayCurrency != l.currency &&
      from != null &&
      to != null &&
      from > 0) {
    value = l.price! * to / from;
    code = displayCurrency;
  }
  final sym = currencySymbol(code);
  final n = _shortNum(value);
  // Symbols like $ / € lead the number; word-ish codes (сум, lei, KZT) trail it.
  return sym.length <= 1 ? '$sym$n' : '$n $sym';
}

String _shortNum(num v) {
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000) {
    final thousands = v / 1000;
    // Do not turn 2,500 into 3K. Keep one decimal below 10K and remove a
    // redundant trailing .0 (2,000 -> 2K, 2,500 -> 2.5K).
    final digits = thousands < 10 ? 1 : 0;
    return '${thousands.toStringAsFixed(digits).replaceFirst(RegExp(r'\.0$'), '')}K';
  }
  return v.round().toString();
}

String propertyLabel(String type, [AppStrings? s]) => type == 'house'
    ? (s?.t('house') ?? 'House')
    : (s?.t('apartment') ?? 'Apartment');

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

/// Relative "posted N ago" label from a listing's createdAt, or null.
String? postedLabel(DateTime? createdAt, [AppStrings? s]) {
  if (createdAt == null) return null;
  final d = DateTime.now().difference(createdAt);
  if (d.inDays >= 1)
    return s?.t('daysAgo', {'n': '${d.inDays}'}) ?? '${d.inDays}d ago';
  if (d.inHours >= 1)
    return s?.t('hoursAgo', {'n': '${d.inHours}'}) ?? '${d.inHours}h ago';
  return s?.t('justNow') ?? 'Just now';
}

/// Translate a backend-derived tag. The backend emits a fixed English
/// vocabulary (furnished, parking, for rent, owner, …) plus dynamic tags
/// (district names, "3 rooms", "commission 50%"). Known tags are localized via
/// the `tag_*` keys; dynamic/unknown tags (place names, ЖК) pass through as-is.
String tagLabel(String tag, [AppStrings? s]) {
  if (s == null) return tag;
  // "N rooms" -> localized rooms label.
  final rooms = RegExp(r'^(\d+)\s+rooms?$').firstMatch(tag);
  if (rooms != null) return s.t('roomsN', {'n': rooms.group(1)!});
  // "commission N%" -> localized commission label with the percentage.
  final comm = RegExp(r'^commission\s+(\d+)%$').firstMatch(tag);
  if (comm != null) return '${s.t('commission')} ${comm.group(1)}%';
  final key = _tagKeys[tag];
  return key != null ? s.t(key) : tag;
}

/// Fixed-vocabulary tag -> l10n key. Anything not listed passes through as-is.
const _tagKeys = <String, String>{
  'furnished': 'tag_furnished',
  'unfurnished': 'tag_unfurnished',
  'renovated': 'tag_renovated',
  'new build': 'tag_newBuild',
  'parking': 'tag_parking',
  'balcony': 'tag_balcony',
  'elevator': 'tag_elevator',
  'pets ok': 'petsAllowed',
  'children ok': 'childrenAllowed',
  'no agency': 'tag_noAgency',
  'utilities included': 'tag_utilities',
  'studio': 'tag_studio',
  'air conditioning': 'tag_ac',
  'microwave': 'tag_microwave',
  'dishwasher': 'tag_dishwasher',
  'washing machine': 'tag_washingMachine',
  'central heating': 'tag_heating',
  'pool': 'tag_pool',
  'negotiable': 'tag_negotiable',
  'for rent': 'tag_forRent',
  'for sale': 'saleLong',
  'long-term rent': 'longRentLong',
  'short-term rent': 'shortRentLong',
  'girls only': 'women',
  'men only': 'men',
  'family': 'family',
  'agency': 'agency',
  'owner': 'owner',
  'room only': 'roomOnly',
  'deposit': 'deposit',
  'commission': 'commission',
  'no commission': 'tag_noCommission',
};

const countryFlags = {'RO': '🇷🇴', 'UA': '🇺🇦', 'KZ': '🇰🇿', 'UZ': '🇺🇿'};

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

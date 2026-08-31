from pathlib import Path
import re

# api_service.dart
path = Path('app/lib/services/api_service.dart')
text = path.read_text(encoding='utf-8')
text = text.replace("import '../models/listing.dart';\n", "import '../models/listing.dart';\nimport '../models/map_listing_point.dart';\n", 1)
old = '''  Future<List<Listing>> fetchMapListings(Filters filters) async {\n    final params = Map<String, String>.from(filters.toQueryParams())\n      ..['mapOnly'] = 'true';\n    final uri =\n        Uri.parse('$baseUrl/api/listings').replace(queryParameters: params);\n    final res = await http.get(uri).timeout(const Duration(seconds: 30));\n    if (res.statusCode != 200) return const [];\n    final json = jsonDecode(res.body) as Map<String, dynamic>;\n    return ((json['mapPoints'] as List?) ?? const [])\n        .map((point) => Listing.fromJson(point as Map<String, dynamic>))\n        .toList();\n  }\n'''
new = '''  Future<List<MapListingPoint>> fetchMapListings(Filters filters) async {\n    final params = Map<String, String>.from(filters.toQueryParams())\n      ..['mapOnly'] = 'true';\n    final uri =\n        Uri.parse('$baseUrl/api/listings').replace(queryParameters: params);\n    final res = await http.get(uri).timeout(const Duration(seconds: 30));\n    if (res.statusCode != 200) return const [];\n    final json = jsonDecode(res.body) as Map<String, dynamic>;\n    return ((json['mapPoints'] as List?) ?? const []).map((raw) {\n      final point = Map<String, dynamic>.from(raw as Map);\n      if (point['photo'] != null) point['photo'] = _resolvePhoto(point['photo']);\n      return MapListingPoint.fromJson(point);\n    }).toList();\n  }\n'''
if old not in text: raise SystemExit('fetchMapListings block not found')
path.write_text(text.replace(old, new, 1), encoding='utf-8')

# app_state.dart
path = Path('app/lib/state/app_state.dart')
text = path.read_text(encoding='utf-8')
text = text.replace("import '../models/listing_identity.dart';\n", "import '../models/listing_identity.dart';\nimport '../models/map_listing_point.dart';\n", 1)
text = text.replace('  List<Listing> mapListings = [];\n', '  List<MapListingPoint> mapListings = [];\n', 1)
path.write_text(text, encoding='utf-8')

# hidden.dart
path = Path('app/lib/state/hidden.dart')
text = path.read_text(encoding='utf-8')
old = '''  bool isHidden(Listing listing) {\n    final key = listingKey(listing);\n    return _items.any((item) => listingKey(item) == key);\n  }\n'''
new = '''  bool isHiddenKey(String key) =>\n      _items.any((item) => listingKey(item) == key);\n\n  bool isHidden(Listing listing) => isHiddenKey(listingKey(listing));\n'''
if old not in text: raise SystemExit('hidden lookup block not found')
path.write_text(text.replace(old, new, 1), encoding='utf-8')

# sorted.dart
path = Path('app/lib/state/sorted.dart')
text = path.read_text(encoding='utf-8')
old = '''  bool contains(Listing listing) {\n    final key = listingKey(listing);\n    return _collections.any(\n      (collection) => collection.items.any((item) => listingKey(item) == key),\n    );\n  }\n\n  bool containsListing(Listing listing) => contains(listing);\n'''
new = '''  bool containsKey(String key) => _collections.any(\n        (collection) =>\n            collection.items.any((item) => listingKey(item) == key),\n      );\n\n  bool contains(Listing listing) => containsKey(listingKey(listing));\n\n  bool containsListing(Listing listing) => contains(listing);\n'''
if old not in text: raise SystemExit('sorted lookup block not found')
path.write_text(text.replace(old, new, 1), encoding='utf-8')

# format.dart
path = Path('app/lib/utils/format.dart')
text = path.read_text(encoding='utf-8')
old = '''String pinPriceLabel(\n  Listing l, {\n  Map<String, double>? rates,\n  String? displayCurrency,\n}) {\n  if (l.price == null) return '—';\n  var value = l.price!;\n  var code = l.currency;\n  final from = rates?[l.currency];\n  final to = displayCurrency == null ? null : rates?[displayCurrency];\n  if (displayCurrency != null &&\n      displayCurrency != l.currency &&\n      from != null &&\n      to != null &&\n      from > 0) {\n    value = l.price! * to / from;\n    code = displayCurrency;\n  }\n  final sym = currencySymbol(code);\n  final n = _shortNum(value);\n  // Symbols like $ / € lead the number; word-ish codes (сум, lei, KZT) trail it.\n  return sym.length <= 1 ? '$sym$n' : '$n $sym';\n}\n'''
new = '''String pinPriceLabelValues(\n  num? price,\n  String currency, {\n  Map<String, double>? rates,\n  String? displayCurrency,\n}) {\n  if (price == null) return '—';\n  var value = price;\n  var code = currency;\n  final from = rates?[currency];\n  final to = displayCurrency == null ? null : rates?[displayCurrency];\n  if (displayCurrency != null &&\n      displayCurrency != currency &&\n      from != null &&\n      to != null &&\n      from > 0) {\n    value = price * to / from;\n    code = displayCurrency;\n  }\n  final sym = currencySymbol(code);\n  final n = _shortNum(value);\n  // Symbols like $ / € lead the number; word-ish codes (сум, lei, KZT) trail it.\n  return sym.length <= 1 ? '$sym$n' : '$n $sym';\n}\n\nString pinPriceLabel(\n  Listing l, {\n  Map<String, double>? rates,\n  String? displayCurrency,\n}) => pinPriceLabelValues(\n  l.price,\n  l.currency,\n  rates: rates,\n  displayCurrency: displayCurrency,\n);\n'''
if old not in text: raise SystemExit('pinPriceLabel block not found')
path.write_text(text.replace(old, new, 1), encoding='utf-8')

# price_tone.dart
path = Path('app/lib/utils/price_tone.dart')
text = path.read_text(encoding='utf-8')
old = '''double? listingPriceUsd(Listing listing, Map<String, double> rates) {\n  final price = listing.price?.toDouble();\n  final rate = rates[listing.currency];\n  if (price == null || rate == null || rate <= 0) return null;\n  return price / rate;\n}\n\n/// The tone for one listing, defaulting to pink when there's no market\n/// comparison — matches the site's card/popup behavior of never falling\n/// back to a neutral/white price.\nPriceTone listingPriceTone(Listing listing, Map<String, double> rates) {\n  final priceUsd = listingPriceUsd(listing, rates);\n  final medianUsd = listing.marketComparison?.medianUsd?.toDouble();\n  return flatPriceTone(priceUsd, medianUsd) ?? PriceTone.pink;\n}\n'''
new = '''double? priceUsdForValues(\n  num? price,\n  String currency,\n  Map<String, double> rates,\n) {\n  final value = price?.toDouble();\n  final rate = rates[currency];\n  if (value == null || rate == null || rate <= 0) return null;\n  return value / rate;\n}\n\ndouble? listingPriceUsd(Listing listing, Map<String, double> rates) =>\n    priceUsdForValues(listing.price, listing.currency, rates);\n\nPriceTone priceToneForValues({\n  required num? price,\n  required String currency,\n  required num? medianUsd,\n  required Map<String, double> rates,\n}) {\n  final priceUsd = priceUsdForValues(price, currency, rates);\n  return flatPriceTone(priceUsd, medianUsd?.toDouble()) ?? PriceTone.pink;\n}\n\n/// The tone for one listing, defaulting to pink when there's no market\n/// comparison — matches the site's card/popup behavior of never falling\n/// back to a neutral/white price.\nPriceTone listingPriceTone(Listing listing, Map<String, double> rates) =>\n    priceToneForValues(\n      price: listing.price,\n      currency: listing.currency,\n      medianUsd: listing.marketComparison?.medianUsd,\n      rates: rates,\n    );\n'''
if old not in text: raise SystemExit('price tone block not found')
path.write_text(text.replace(old, new, 1), encoding='utf-8')

# home_screen.dart
path = Path('app/lib/screens/home_screen.dart')
text = path.read_text(encoding='utf-8')
text = text.replace("import '../models/listing_identity.dart';\n", "import '../models/listing_identity.dart';\nimport '../models/map_listing_point.dart';\n", 1)
text = text.replace('    List<Listing> listings,\n    LatLng center,\n  ) {', '    List<MapListingPoint> listings,\n    LatLng center,\n  ) {', 1)
old = '''  void _showMapPreview(Listing l) {\n    final state = context.read<AppState>();\n    var initial = l;\n    for (final item in state.listings) {\n      if (sameListing(item, l)) {\n        initial = item;\n        break;\n      }\n    }\n'''
new = '''  void _showMapPreview(MapListingPoint point) {\n    final state = context.read<AppState>();\n    var initial = point.toPreviewListing();\n    for (final item in state.listings) {\n      if (listingKey(item) == point.key) {\n        initial = item;\n        break;\n      }\n    }\n'''
if old not in text: raise SystemExit('map preview block not found')
text = text.replace(old, new, 1)
old = '''      final mapItems = _applyTab(\n        state.mapListings.isNotEmpty ? state.mapListings : listings,\n        hidden,\n        sorted,\n      );\n'''
new = '''      final fallbackMapPoints = <MapListingPoint>[\n        for (final listing in listings)\n          if (listing.hasLocation) MapListingPoint.fromListing(listing),\n      ];\n      final mapItems = _applyMapTab(\n        state.mapListings.isNotEmpty ? state.mapListings : fallbackMapPoints,\n        hidden,\n        sorted,\n      );\n'''
if old not in text: raise SystemExit('map items block not found')
text = text.replace(old, new, 1)
marker = '''  String _emptyLabel(SettingsState settings) => switch (_tab) {\n'''
insert = '''  List<MapListingPoint> _applyMapTab(\n    List<MapListingPoint> points,\n    HiddenState hidden,\n    SortedState sorted,\n  ) {\n    if (_tab == _ViewTab.hidden) {\n      return points.where((point) => hidden.isHiddenKey(point.key)).toList();\n    }\n    return points\n        .where(\n          (point) =>\n              !hidden.isHiddenKey(point.key) && !sorted.containsKey(point.key),\n        )\n        .toList();\n  }\n\n'''
if marker not in text: raise SystemExit('empty label marker not found')
text = text.replace(marker, insert + marker, 1)
path.write_text(text, encoding='utf-8')

# map_view.dart: all Listing type references are map-marker records.
path = Path('app/lib/widgets/map_view.dart')
text = path.read_text(encoding='utf-8')
text = text.replace("import '../models/listing.dart';\n", "import '../models/map_listing_point.dart';\n", 1)
text = re.sub(r'\bListing\b', 'MapListingPoint', text)
text = text.replace('l.hasLocation).toList();', 'true).toList();')
text = text.replace('listing.hasLocation).toList();', 'true).toList();')
text = text.replace('l.lat!', 'l.lat').replace('l.lng!', 'l.lng')
text = text.replace('listing.lat!', 'listing.lat').replace('listing.lng!', 'listing.lng')
text = text.replace("  String _listingKey(MapListingPoint listing) =>\n      '${listing.source}:${listing.country}:${listing.id}';\n", "  String _listingKey(MapListingPoint listing) => listing.key;\n", 1)
old = '''    final label = pinPriceLabel(\n      listing,\n      rates: rates,\n      displayCurrency: displayCurrency,\n    );\n    final color = priceToneColor(listingPriceTone(listing, ratesOrEmpty));\n'''
new = '''    final label = pinPriceLabelValues(\n      listing.price,\n      listing.currency,\n      rates: rates,\n      displayCurrency: displayCurrency,\n    );\n    final color = priceToneColor(\n      priceToneForValues(\n        price: listing.price,\n        currency: listing.currency,\n        medianUsd: listing.marketMedianUsd,\n        rates: ratesOrEmpty,\n      ),\n    );\n'''
if old not in text: raise SystemExit('standalone price block not found')
text = text.replace(old, new, 1)
old = '''    final color = priceToneColor(listingPriceTone(listing, ratesOrEmpty));\n    final price = pinPriceLabel(\n      listing,\n      rates: rates,\n      displayCurrency: displayCurrency,\n    );\n'''
new = '''    final color = priceToneColor(\n      priceToneForValues(\n        price: listing.price,\n        currency: listing.currency,\n        medianUsd: listing.marketMedianUsd,\n        rates: ratesOrEmpty,\n      ),\n    );\n    final price = pinPriceLabelValues(\n      listing.price,\n      listing.currency,\n      rates: rates,\n      displayCurrency: displayCurrency,\n    );\n'''
if old not in text: raise SystemExit('radial price block not found')
text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8')

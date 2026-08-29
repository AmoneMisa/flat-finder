/// Search filters mirrored by the backend query params.
enum PropertyType { any, flat, house }

/// Deal type. `name` matches the backend query value (sale/longRent/shortRent).
enum DealType { any, sale, longRent, shortRent }

enum AgencyFilter { any, owner, agency }

/// Stated tenant restriction. `name` matches the backend value (women/men/family).
enum Audience { any, women, men, family }

/// Client-side result ordering. `relevance` keeps the server's original order.
enum SortBy { relevance, dateNew, priceAsc, priceDesc, areaDesc, distanceCenter, distanceMetro }

/// All selectable listing sources. Empty selection on the server means "all".
/// Reddit/Threads are omitted: their public APIs can't be read from the server
/// (datacenter IPs are blocked / no public search), so they never return
/// results and only added dead filter chips.
const kAllSources = ['olx', 'telegram'];

const kSourceLabels = {
  'olx': 'OLX',
  'telegram': 'Telegram',
};

/// Boolean amenity filters the backend accepts as bare `?key=true` query
/// params (`parseListingFilters` in listing-routes.js) and stores generically
/// so new amenities don't need a new Filters field each time.
const kAmenityFilters = [
  'tv', 'microwave', 'oven', 'bidet', 'walkInCloset', 'bathtub', 'shower', 'euroLayout',
];

/// Districts and metro/transit stations available within a single city.
class CityLocations {
  final List<String> districts;
  final List<String> metro;

  const CityLocations({this.districts = const [], this.metro = const []});

  factory CityLocations.fromJson(Map<String, dynamic> j) => CityLocations(
        districts: (j['districts'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        metro: (j['metro'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
}

class Country {
  final String code;
  final String name;
  final String currency;
  final double centerLat;
  final double centerLng;
  final List<String> cities;
  final Map<String, CityLocations> locations; // by city name

  const Country({
    required this.code,
    required this.name,
    required this.currency,
    required this.centerLat,
    required this.centerLng,
    this.cities = const [],
    this.locations = const {},
  });

  factory Country.fromJson(Map<String, dynamic> j) => Country(
        code: j['code'],
        name: j['name'],
        currency: j['currency'] ?? '',
        centerLat: (j['center']?['lat'] as num?)?.toDouble() ?? 0,
        centerLng: (j['center']?['lng'] as num?)?.toDouble() ?? 0,
        cities: (j['cities'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        locations: ((j['locations'] as Map?) ?? const {}).map(
          (k, v) => MapEntry(k.toString(), CityLocations.fromJson(Map<String, dynamic>.from(v))),
        ),
      );
}

class Filters {
  Set<String> countries; // selected country codes
  Set<String> sources; // selected listing sources
  List<String> customSources; // user-added source URLs (JSON-LD / RSS pages)
  PropertyType propertyType;
  DealType dealType;
  AgencyFilter agency;
  Audience audience;
  num? priceMin;
  num? priceMax;
  num? priceTolerance; // allow results up to priceMax + this
  num? roomsMin;
  num? roomsMax;
  num? bedroomsMin;
  num? bedroomsMax;
  num? floorMin;
  num? floorMax;
  num? yearMin;
  num? yearMax;
  String city;
  String district;
  String metro;
  String query;
  bool pets; // require "pets allowed"
  bool children; // require "children allowed"
  bool roomOnly; // only partial / room-share rentals
  Set<String> amenities; // subset of kAmenityFilters required present
  bool noElevator;
  bool noDeposit;
  bool communalIncluded;
  bool noCommission;
  int? maxAgeDays; // only posts newer than this many days
  SortBy sort; // client-side ordering (not sent to the server)

  Filters({
    Set<String>? countries,
    Set<String>? sources,
    List<String>? customSources,
    this.propertyType = PropertyType.any,
    this.dealType = DealType.any,
    this.agency = AgencyFilter.any,
    this.audience = Audience.any,
    this.priceMin,
    this.priceMax,
    this.priceTolerance,
    this.roomsMin,
    this.roomsMax,
    this.bedroomsMin,
    this.bedroomsMax,
    this.floorMin,
    this.floorMax,
    this.yearMin,
    this.yearMax,
    this.city = '',
    this.district = '',
    this.metro = '',
    this.query = '',
    this.pets = false,
    this.children = false,
    this.roomOnly = false,
    Set<String>? amenities,
    this.noElevator = false,
    this.noDeposit = false,
    this.communalIncluded = false,
    this.noCommission = false,
    this.maxAgeDays,
    this.sort = SortBy.relevance,
  })  : countries = countries ?? {'RO'},
        sources = sources ?? {...kAllSources},
        customSources = customSources ?? [],
        amenities = amenities ?? {};

  Filters copyWith({
    Set<String>? countries,
    Set<String>? sources,
    List<String>? customSources,
    PropertyType? propertyType,
    DealType? dealType,
    AgencyFilter? agency,
    Audience? audience,
    num? priceMin,
    num? priceMax,
    num? priceTolerance,
    num? roomsMin,
    num? roomsMax,
    num? bedroomsMin,
    num? bedroomsMax,
    num? floorMin,
    num? floorMax,
    num? yearMin,
    num? yearMax,
    bool clearPriceMin = false,
    bool clearPriceMax = false,
    bool clearPriceTolerance = false,
    bool clearRoomsMin = false,
    bool clearRoomsMax = false,
    bool clearBedroomsMin = false,
    bool clearBedroomsMax = false,
    bool clearFloorMin = false,
    bool clearFloorMax = false,
    bool clearYearMin = false,
    bool clearYearMax = false,
    String? city,
    String? district,
    String? metro,
    String? query,
    bool? pets,
    bool? children,
    bool? roomOnly,
    Set<String>? amenities,
    bool? noElevator,
    bool? noDeposit,
    bool? communalIncluded,
    bool? noCommission,
    int? maxAgeDays,
    bool clearMaxAgeDays = false,
    SortBy? sort,
  }) {
    return Filters(
      countries: countries ?? this.countries,
      sources: sources ?? this.sources,
      customSources: customSources ?? this.customSources,
      propertyType: propertyType ?? this.propertyType,
      dealType: dealType ?? this.dealType,
      agency: agency ?? this.agency,
      audience: audience ?? this.audience,
      priceMin: clearPriceMin ? null : (priceMin ?? this.priceMin),
      priceMax: clearPriceMax ? null : (priceMax ?? this.priceMax),
      priceTolerance:
          clearPriceTolerance ? null : (priceTolerance ?? this.priceTolerance),
      roomsMin: clearRoomsMin ? null : (roomsMin ?? this.roomsMin),
      roomsMax: clearRoomsMax ? null : (roomsMax ?? this.roomsMax),
      bedroomsMin: clearBedroomsMin ? null : (bedroomsMin ?? this.bedroomsMin),
      bedroomsMax: clearBedroomsMax ? null : (bedroomsMax ?? this.bedroomsMax),
      floorMin: clearFloorMin ? null : (floorMin ?? this.floorMin),
      floorMax: clearFloorMax ? null : (floorMax ?? this.floorMax),
      yearMin: clearYearMin ? null : (yearMin ?? this.yearMin),
      yearMax: clearYearMax ? null : (yearMax ?? this.yearMax),
      city: city ?? this.city,
      district: district ?? this.district,
      metro: metro ?? this.metro,
      query: query ?? this.query,
      pets: pets ?? this.pets,
      children: children ?? this.children,
      roomOnly: roomOnly ?? this.roomOnly,
      amenities: amenities ?? this.amenities,
      noElevator: noElevator ?? this.noElevator,
      noDeposit: noDeposit ?? this.noDeposit,
      communalIncluded: communalIncluded ?? this.communalIncluded,
      noCommission: noCommission ?? this.noCommission,
      maxAgeDays: clearMaxAgeDays ? null : (maxAgeDays ?? this.maxAgeDays),
      sort: sort ?? this.sort,
    );
  }

  /// Serialize the user's selections so they survive app restarts. Only the
  /// fields the user actively picks are stored (not derived/UI state).
  Map<String, dynamic> toJson() => {
        'countries': countries.toList(),
        'sources': sources.toList(),
        'customSources': customSources,
        'propertyType': propertyType.name,
        'dealType': dealType.name,
        'agency': agency.name,
        'audience': audience.name,
        'priceMin': priceMin,
        'priceMax': priceMax,
        'priceTolerance': priceTolerance,
        'roomsMin': roomsMin,
        'roomsMax': roomsMax,
        'bedroomsMin': bedroomsMin,
        'bedroomsMax': bedroomsMax,
        'floorMin': floorMin,
        'floorMax': floorMax,
        'yearMin': yearMin,
        'yearMax': yearMax,
        'city': city,
        'district': district,
        'metro': metro,
        'query': query,
        'pets': pets,
        'children': children,
        'roomOnly': roomOnly,
        'amenities': amenities.toList(),
        'noElevator': noElevator,
        'noDeposit': noDeposit,
        'communalIncluded': communalIncluded,
        'noCommission': noCommission,
        'maxAgeDays': maxAgeDays,
        'sort': sort.name,
      };

  factory Filters.fromJson(Map<String, dynamic> j) {
    T byName<T extends Enum>(List<T> values, dynamic name, T fallback) {
      for (final v in values) {
        if (v.name == name) return v;
      }
      return fallback;
    }

    Set<String> strSet(dynamic v, Set<String> fallback) =>
        (v is List && v.isNotEmpty) ? v.map((e) => e.toString()).toSet() : fallback;
    num? n(dynamic v) => v == null ? null : (v as num);

    return Filters(
      countries: strSet(j['countries'], {'RO'}),
      sources: strSet(j['sources'], {...kAllSources}),
      customSources: (j['customSources'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList() ??
          [],
      propertyType: byName(PropertyType.values, j['propertyType'], PropertyType.any),
      dealType: byName(DealType.values, j['dealType'], DealType.any),
      agency: byName(AgencyFilter.values, j['agency'], AgencyFilter.any),
      audience: byName(Audience.values, j['audience'], Audience.any),
      priceMin: n(j['priceMin']),
      priceMax: n(j['priceMax']),
      priceTolerance: n(j['priceTolerance']),
      roomsMin: n(j['roomsMin']),
      roomsMax: n(j['roomsMax']),
      bedroomsMin: n(j['bedroomsMin']),
      bedroomsMax: n(j['bedroomsMax']),
      floorMin: n(j['floorMin']),
      floorMax: n(j['floorMax']),
      yearMin: n(j['yearMin']),
      yearMax: n(j['yearMax']),
      city: (j['city'] ?? '').toString(),
      district: (j['district'] ?? '').toString(),
      metro: (j['metro'] ?? '').toString(),
      query: (j['query'] ?? '').toString(),
      pets: j['pets'] == true,
      children: j['children'] == true,
      roomOnly: j['roomOnly'] == true,
      amenities: (j['amenities'] as List?)
              ?.map((e) => e.toString())
              .where(kAmenityFilters.contains)
              .toSet() ??
          {},
      noElevator: j['noElevator'] == true,
      noDeposit: j['noDeposit'] == true,
      communalIncluded: j['communalIncluded'] == true,
      noCommission: j['noCommission'] == true,
      maxAgeDays: (j['maxAgeDays'] as num?)?.toInt(),
      sort: byName(SortBy.values, j['sort'], SortBy.relevance),
    );
  }

  /// Parse filters from a shared deep-link's query parameters (the inverse of
  /// [toQueryParams], plus the client-only `sort` field). Unknown/missing keys
  /// fall back to defaults, so a partial or hand-edited link still works.
  factory Filters.fromQueryParams(Map<String, String> q) {
    T byName<T extends Enum>(List<T> values, String? name, T fallback) {
      for (final v in values) {
        if (v.name == name) return v;
      }
      return fallback;
    }

    num? n(String? v) => (v == null || v.isEmpty) ? null : num.tryParse(v);
    Set<String> csv(String? v) => (v == null || v.isEmpty)
        ? <String>{}
        : v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();

    final countries = csv(q['countries']);
    final sources = csv(q['sources']);
    return Filters(
      countries: countries.isEmpty ? {'RO'} : countries,
      sources: sources.isEmpty ? {...kAllSources} : sources,
      customSources: (q['customSources'] ?? '')
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      propertyType: byName(PropertyType.values, q['propertyType'], PropertyType.any),
      dealType: byName(DealType.values, q['dealType'], DealType.any),
      agency: byName(AgencyFilter.values, q['agency'], AgencyFilter.any),
      audience: byName(Audience.values, q['audience'], Audience.any),
      priceMin: n(q['priceMin']),
      priceMax: n(q['priceMax']),
      priceTolerance: n(q['priceTolerance']),
      roomsMin: n(q['roomsMin']),
      roomsMax: n(q['roomsMax']),
      bedroomsMin: n(q['bedroomsMin']),
      bedroomsMax: n(q['bedroomsMax']),
      floorMin: n(q['floorMin']),
      floorMax: n(q['floorMax']),
      yearMin: n(q['yearMin']),
      yearMax: n(q['yearMax']),
      city: (q['city'] ?? '').trim(),
      district: (q['district'] ?? '').trim(),
      metro: (q['metro'] ?? '').trim(),
      query: (q['query'] ?? '').trim(),
      pets: q['pets'] == 'true',
      children: q['children'] == 'true',
      roomOnly: q['roomOnly'] == 'true',
      amenities: kAmenityFilters.where((key) => q[key] == 'true').toSet(),
      noElevator: q['noElevator'] == 'true',
      noDeposit: q['noDeposit'] == 'true',
      communalIncluded: q['communalIncluded'] == 'true',
      noCommission: q['noCommission'] == 'true',
      maxAgeDays: int.tryParse(q['maxAgeDays'] ?? ''),
      sort: byName(SortBy.values, q['sort'], SortBy.relevance),
    );
  }

  Map<String, String> toQueryParams() {
    final p = <String, String>{
      'countries': countries.join(','),
      'limit': '50',
    };
    // "Any" means "don't filter", so we simply omit those params server-side.
    if (propertyType != PropertyType.any) p['propertyType'] = propertyType.name;
    if (dealType != DealType.any) p['dealType'] = dealType.name;
    if (agency != AgencyFilter.any) p['agency'] = agency.name;
    if (audience != Audience.any) p['audience'] = audience.name;
    if (pets) p['pets'] = 'true';
    if (children) p['children'] = 'true';
    if (roomOnly) p['roomOnly'] = 'true';
    for (final key in amenities) {
      if (kAmenityFilters.contains(key)) p[key] = 'true';
    }
    if (noElevator) p['noElevator'] = 'true';
    if (noDeposit) p['noDeposit'] = 'true';
    if (communalIncluded) p['communalIncluded'] = 'true';
    if (noCommission) p['noCommission'] = 'true';
    if (maxAgeDays != null && maxAgeDays! > 0) p['maxAgeDays'] = maxAgeDays.toString();
    // Only send when it's a real subset; all-selected means "all" server-side.
    if (sources.isNotEmpty && sources.length < kAllSources.length) {
      p['sources'] = sources.join(',');
    }
    if (customSources.isNotEmpty) {
      p['customSources'] = customSources.join(',');
    }
    if (priceMin != null) p['priceMin'] = priceMin.toString();
    if (priceMax != null) p['priceMax'] = priceMax.toString();
    // Tolerance only makes sense with a max price set.
    if (priceMax != null && priceTolerance != null && priceTolerance! > 0) {
      p['priceTolerance'] = priceTolerance.toString();
    }
    if (roomsMin != null) p['roomsMin'] = roomsMin.toString();
    if (roomsMax != null) p['roomsMax'] = roomsMax.toString();
    if (bedroomsMin != null) p['bedroomsMin'] = bedroomsMin.toString();
    if (bedroomsMax != null) p['bedroomsMax'] = bedroomsMax.toString();
    if (floorMin != null) p['floorMin'] = floorMin.toString();
    if (floorMax != null) p['floorMax'] = floorMax.toString();
    if (yearMin != null) p['yearMin'] = yearMin.toString();
    if (yearMax != null) p['yearMax'] = yearMax.toString();
    if (city.trim().isNotEmpty) p['city'] = city.trim();
    if (district.trim().isNotEmpty) p['district'] = district.trim();
    if (metro.trim().isNotEmpty) p['metro'] = metro.trim();
    if (query.trim().isNotEmpty) p['query'] = query.trim();
    return p;
  }
}

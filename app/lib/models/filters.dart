/// Search filters mirrored by the backend query params.
enum PropertyType { any, flat, house }

/// Deal type. `name` matches the backend query value (sale/longRent/shortRent).
enum DealType { any, sale, longRent, shortRent }

enum AgencyFilter { any, owner, agency }

/// Stated tenant restriction. `name` matches the backend value (women/men/family).
enum Audience { any, women, men, family }

/// All selectable listing sources. Empty selection on the server means "all".
const kAllSources = ['olx', 'reddit', 'telegram', 'threads'];

const kSourceLabels = {
  'olx': 'OLX',
  'reddit': 'Reddit',
  'telegram': 'Telegram',
  'threads': 'Threads',
};

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
  PropertyType propertyType;
  DealType dealType;
  AgencyFilter agency;
  Audience audience;
  num? priceMin;
  num? priceMax;
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

  Filters({
    Set<String>? countries,
    Set<String>? sources,
    this.propertyType = PropertyType.any,
    this.dealType = DealType.any,
    this.agency = AgencyFilter.any,
    this.audience = Audience.any,
    this.priceMin,
    this.priceMax,
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
  })  : countries = countries ?? {'RO'},
        sources = sources ?? {...kAllSources};

  Filters copyWith({
    Set<String>? countries,
    Set<String>? sources,
    PropertyType? propertyType,
    DealType? dealType,
    AgencyFilter? agency,
    Audience? audience,
    num? priceMin,
    num? priceMax,
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
  }) {
    return Filters(
      countries: countries ?? this.countries,
      sources: sources ?? this.sources,
      propertyType: propertyType ?? this.propertyType,
      dealType: dealType ?? this.dealType,
      agency: agency ?? this.agency,
      audience: audience ?? this.audience,
      priceMin: clearPriceMin ? null : (priceMin ?? this.priceMin),
      priceMax: clearPriceMax ? null : (priceMax ?? this.priceMax),
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
    );
  }

  /// Serialize the user's selections so they survive app restarts. Only the
  /// fields the user actively picks are stored (not derived/UI state).
  Map<String, dynamic> toJson() => {
        'countries': countries.toList(),
        'sources': sources.toList(),
        'propertyType': propertyType.name,
        'dealType': dealType.name,
        'agency': agency.name,
        'audience': audience.name,
        'priceMin': priceMin,
        'priceMax': priceMax,
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
      propertyType: byName(PropertyType.values, j['propertyType'], PropertyType.any),
      dealType: byName(DealType.values, j['dealType'], DealType.any),
      agency: byName(AgencyFilter.values, j['agency'], AgencyFilter.any),
      audience: byName(Audience.values, j['audience'], Audience.any),
      priceMin: n(j['priceMin']),
      priceMax: n(j['priceMax']),
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
    );
  }

  Map<String, String> toQueryParams() {
    final p = <String, String>{
      'countries': countries.join(','),
      'propertyType': propertyType.name,
      'dealType': dealType.name,
      'agency': agency.name,
      'audience': audience.name,
      'limit': '50',
    };
    // Only send when it's a real subset; all-selected means "all" server-side.
    if (sources.isNotEmpty && sources.length < kAllSources.length) {
      p['sources'] = sources.join(',');
    }
    if (priceMin != null) p['priceMin'] = priceMin.toString();
    if (priceMax != null) p['priceMax'] = priceMax.toString();
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

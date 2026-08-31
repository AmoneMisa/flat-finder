/// Search filters mirrored by the backend query params.
enum PropertyType { any, flat, house }

/// Deal type. `name` matches the backend query value (sale/longRent/shortRent).
enum DealType { any, sale, longRent, shortRent }

enum AgencyFilter { any, owner, agency }

/// Stated tenant restriction. `name` matches the backend value (women/men/family).
enum Audience { any, women, men, family }

/// Client-side result ordering. `relevance` keeps the server's original order.
enum SortBy {
  relevance,
  dateNew,
  dateOld,
  priceAsc,
  priceDesc,
  titleAsc,
  titleDesc,
  areaDesc,
  distanceCenter,
  distanceMetro,
}

/// All selectable listing sources. Empty selection on the server means "all".
/// Curated owner/realtor websites are persisted as `custom`, so it must be part
/// of the default set or those listings disappear from normal mobile searches.
const kAllSources = ['olx', 'telegram', 'custom'];

const kSourceLabels = {
  'olx': 'OLX',
  'telegram': 'Telegram',
  'custom': 'Sites',
};

/// Boolean amenity filters the backend accepts as bare `?key=true` query
/// params (`parseListingFilters` in listing-routes.js) and stores generically
/// so new amenities don't need a new Filters field each time.
const kAmenityFilters = [
  'dishwasher',
  'airConditioner',
  'parking',
  'internet',
  'gas',
  'balcony',
  'terrace',
  'privateYard',
  'newBuilding',
  'tv',
  'microwave',
  'oven',
  'bidet',
  'walkInCloset',
  'bathtub',
  'shower',
  'euroLayout',
];

/// Landmark kinds the backend's `nearbyKind` filter accepts (paired with
/// `nearbyMaxM`) — matches the categories nearby-places.js indexes listings by.
const kNearbyKinds = [
  'metro',
  'landmark',
  'mall',
  'supermarket',
  'market',
  'pharmacy',
  'clinic',
  'school',
  'kindergarten',
  'park',
  'historic',
  'cinema',
  'transport',
];

Set<String> _singleCountry(Set<String>? values, [String fallback = 'RO']) {
  if (values == null || values.isEmpty) return {fallback};
  return {values.first};
}

Map<String, String> _stringMap(dynamic v) => v is Map
    ? v.map((k, val) => MapEntry(k.toString(), val.toString()))
    : const {};

Set<String> _storedSources(dynamic value) {
  final sources = (value is List && value.isNotEmpty)
      ? value.map((item) => item.toString()).toSet()
      : {...kAllSources};

  // Before curated websites became a selectable source, the complete/default
  // source set was exactly OLX + Telegram. Upgrade that persisted default so
  // existing installs gain Sites too. Narrower explicit selections stay intact.
  const legacyAllSources = {'olx', 'telegram'};
  if (sources.length == legacyAllSources.length &&
      sources.containsAll(legacyAllSources)) {
    return {...sources, 'custom'};
  }
  return sources;
}

/// Districts and metro/transit stations available within a single city.
/// The `*Labels` maps (raw name -> localized label) are only populated when
/// `/api/countries` was fetched with a `locale` — see
/// `ApiService.fetchCountries` and `geographyDisplayName` on the backend.
class CityLocations {
  final List<String> districts;
  final List<String> metro;
  final List<String> microdistricts;
  final List<String> quartals;
  final List<String> areas;
  final Map<String, String> districtLabels;
  final Map<String, String> metroLabels;
  final Map<String, String> microdistrictLabels;
  final Map<String, String> quartalLabels;
  final Map<String, String> areaLabels;

  const CityLocations({
    this.districts = const [],
    this.metro = const [],
    this.microdistricts = const [],
    this.quartals = const [],
    this.areas = const [],
    this.districtLabels = const {},
    this.metroLabels = const {},
    this.microdistrictLabels = const {},
    this.quartalLabels = const {},
    this.areaLabels = const {},
  });

  factory CityLocations.fromJson(Map<String, dynamic> j) => CityLocations(
        districts:
            (j['districts'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        metro: (j['metro'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        microdistricts:
            (j['microdistricts'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        quartals: (j['quartals'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        areas: (j['areas'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        districtLabels: _stringMap(j['districtLabels']),
        metroLabels: _stringMap(j['metroLabels']),
        microdistrictLabels: _stringMap(j['microdistrictLabels']),
        quartalLabels: _stringMap(j['quartalLabels']),
        areaLabels: _stringMap(j['areaLabels']),
      );

  String labelFor(String value, {String? kind}) {
    final typed = switch (kind) {
      'district' => districtLabels[value],
      'metro' => metroLabels[value],
      'microdistrict' => microdistrictLabels[value],
      'quartal' || 'mahalla' => quartalLabels[value],
      'area' || 'local_area' => areaLabels[value],
      _ => null,
    };
    if (typed != null && typed.isNotEmpty) return typed;
    for (final labels in [
      districtLabels,
      microdistrictLabels,
      quartalLabels,
      areaLabels,
      metroLabels,
    ]) {
      final label = labels[value];
      if (label != null && label.isNotEmpty) return label;
    }
    return value;
  }
}

class Country {
  final String code;
  final String name;
  final String currency;
  final String? callingCode;
  final double centerLat;
  final double centerLng;
  final List<String> cities;
  final Map<String, CityLocations> locations; // by city name
  final Map<String, String> cityLabels; // raw city name -> localized label

  const Country({
    required this.code,
    required this.name,
    required this.currency,
    this.callingCode,
    required this.centerLat,
    required this.centerLng,
    this.cities = const [],
    this.locations = const {},
    this.cityLabels = const {},
  });

  /// The display label for [city] — its localized name if the country was
  /// fetched with a `locale` and a translation exists, otherwise the raw
  /// name unchanged.
  String cityLabel(String city) => cityLabels[city] ?? city;

  String locationLabel(String city, String value, {String? kind}) {
    final direct = locations[city]?.labelFor(value, kind: kind);
    if (direct != null && direct != value) return direct;
    return locationLabelAnyCity(value, kind: kind);
  }

  String locationLabelAnyCity(String value, {String? kind}) {
    for (final location in locations.values) {
      final label = location.labelFor(value, kind: kind);
      if (label != value) return label;
    }
    return value;
  }

  factory Country.fromJson(Map<String, dynamic> j) => Country(
        code: j['code'],
        name: j['name'],
        currency: j['currency'] ?? '',
        callingCode: j['callingCode']?.toString(),
        centerLat: (j['center']?['lat'] as num?)?.toDouble() ?? 0,
        centerLng: (j['center']?['lng'] as num?)?.toDouble() ?? 0,
        cities: (j['cities'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        locations: ((j['locations'] as Map?) ?? const {}).map(
          (k, v) => MapEntry(
            k.toString(),
            CityLocations.fromJson(Map<String, dynamic>.from(v)),
          ),
        ),
        cityLabels: _stringMap(j['cityLabels']),
      );
}

class Filters {
  Set<String> countries; // exactly one selected country code
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
  num? totalFloorsMin;
  num? totalFloorsMax;
  num? yearMin;
  num? yearMax;
  num? areaMin;
  num? areaMax;
  num? pricePerSqmMin;
  num? pricePerSqmMax;
  num? commissionPercentMin;
  num? commissionPercentMax;
  String? priceCurrency; // which currency priceMin/priceMax are denominated in
  num? metroMaxM; // max distance (meters) from a metro/transit station
  num? nearbyMaxM; // max distance (meters) from nearbyKind
  String? nearbyKind; // one of kNearbyKinds
  num? centerLat;
  num? centerLng;
  num? radiusM;
  bool withPhotos;
  String city;
  String district;
  String microdistrict;
  String quartal;
  String area;
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
    this.totalFloorsMin,
    this.totalFloorsMax,
    this.yearMin,
    this.yearMax,
    this.areaMin,
    this.areaMax,
    this.pricePerSqmMin,
    this.pricePerSqmMax,
    this.commissionPercentMin,
    this.commissionPercentMax,
    this.priceCurrency,
    this.metroMaxM,
    this.nearbyMaxM,
    this.nearbyKind,
    this.centerLat,
    this.centerLng,
    this.radiusM,
    this.withPhotos = false,
    this.city = '',
    this.district = '',
    this.microdistrict = '',
    this.quartal = '',
    this.area = '',
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
  })  : countries = _singleCountry(countries),
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
    num? totalFloorsMin,
    num? totalFloorsMax,
    num? yearMin,
    num? yearMax,
    num? areaMin,
    num? areaMax,
    num? pricePerSqmMin,
    num? pricePerSqmMax,
    num? commissionPercentMin,
    num? commissionPercentMax,
    String? priceCurrency,
    num? metroMaxM,
    num? nearbyMaxM,
    String? nearbyKind,
    num? centerLat,
    num? centerLng,
    num? radiusM,
    bool? withPhotos,
    bool clearPriceMin = false,
    bool clearPriceMax = false,
    bool clearPriceTolerance = false,
    bool clearRoomsMin = false,
    bool clearRoomsMax = false,
    bool clearBedroomsMin = false,
    bool clearBedroomsMax = false,
    bool clearFloorMin = false,
    bool clearFloorMax = false,
    bool clearTotalFloorsMin = false,
    bool clearTotalFloorsMax = false,
    bool clearYearMin = false,
    bool clearYearMax = false,
    bool clearAreaMin = false,
    bool clearAreaMax = false,
    bool clearPricePerSqmMin = false,
    bool clearPricePerSqmMax = false,
    bool clearCommissionPercentMin = false,
    bool clearCommissionPercentMax = false,
    bool clearPriceCurrency = false,
    bool clearMetroMaxM = false,
    bool clearNearbyMaxM = false,
    bool clearNearbyKind = false,
    bool clearRadiusSearch = false,
    String? city,
    String? district,
    String? microdistrict,
    String? quartal,
    String? area,
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
      totalFloorsMin:
          clearTotalFloorsMin ? null : (totalFloorsMin ?? this.totalFloorsMin),
      totalFloorsMax:
          clearTotalFloorsMax ? null : (totalFloorsMax ?? this.totalFloorsMax),
      yearMin: clearYearMin ? null : (yearMin ?? this.yearMin),
      yearMax: clearYearMax ? null : (yearMax ?? this.yearMax),
      areaMin: clearAreaMin ? null : (areaMin ?? this.areaMin),
      areaMax: clearAreaMax ? null : (areaMax ?? this.areaMax),
      pricePerSqmMin:
          clearPricePerSqmMin ? null : (pricePerSqmMin ?? this.pricePerSqmMin),
      pricePerSqmMax:
          clearPricePerSqmMax ? null : (pricePerSqmMax ?? this.pricePerSqmMax),
      commissionPercentMin: clearCommissionPercentMin
          ? null
          : (commissionPercentMin ?? this.commissionPercentMin),
      commissionPercentMax: clearCommissionPercentMax
          ? null
          : (commissionPercentMax ?? this.commissionPercentMax),
      priceCurrency:
          clearPriceCurrency ? null : (priceCurrency ?? this.priceCurrency),
      metroMaxM: clearMetroMaxM ? null : (metroMaxM ?? this.metroMaxM),
      nearbyMaxM: clearNearbyMaxM ? null : (nearbyMaxM ?? this.nearbyMaxM),
      nearbyKind: clearNearbyKind ? null : (nearbyKind ?? this.nearbyKind),
      centerLat: clearRadiusSearch ? null : (centerLat ?? this.centerLat),
      centerLng: clearRadiusSearch ? null : (centerLng ?? this.centerLng),
      radiusM: clearRadiusSearch ? null : (radiusM ?? this.radiusM),
      withPhotos: withPhotos ?? this.withPhotos,
      city: city ?? this.city,
      district: district ?? this.district,
      microdistrict: microdistrict ?? this.microdistrict,
      quartal: quartal ?? this.quartal,
      area: area ?? this.area,
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
        'totalFloorsMin': totalFloorsMin,
        'totalFloorsMax': totalFloorsMax,
        'yearMin': yearMin,
        'yearMax': yearMax,
        'areaMin': areaMin,
        'areaMax': areaMax,
        'pricePerSqmMin': pricePerSqmMin,
        'pricePerSqmMax': pricePerSqmMax,
        'commissionPercentMin': commissionPercentMin,
        'commissionPercentMax': commissionPercentMax,
        'priceCurrency': priceCurrency,
        'metroMaxM': metroMaxM,
        'nearbyMaxM': nearbyMaxM,
        'nearbyKind': nearbyKind,
        'centerLat': centerLat,
        'centerLng': centerLng,
        'radiusM': radiusM,
        'withPhotos': withPhotos,
        'city': city,
        'district': district,
        'microdistrict': microdistrict,
        'quartal': quartal,
        'area': area,
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
        (v is List && v.isNotEmpty)
            ? v.map((e) => e.toString()).toSet()
            : fallback;
    num? n(dynamic v) => v == null ? null : (v as num);

    return Filters(
      countries: strSet(j['countries'], {'RO'}),
      sources: _storedSources(j['sources']),
      customSources: (j['customSources'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList() ??
          [],
      propertyType: byName(
        PropertyType.values,
        j['propertyType'],
        PropertyType.any,
      ),
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
      totalFloorsMin: n(j['totalFloorsMin']),
      totalFloorsMax: n(j['totalFloorsMax']),
      yearMin: n(j['yearMin']),
      yearMax: n(j['yearMax']),
      areaMin: n(j['areaMin']),
      areaMax: n(j['areaMax']),
      pricePerSqmMin: n(j['pricePerSqmMin']),
      pricePerSqmMax: n(j['pricePerSqmMax']),
      commissionPercentMin: n(j['commissionPercentMin']),
      commissionPercentMax: n(j['commissionPercentMax']),
      priceCurrency: j['priceCurrency'] as String?,
      metroMaxM: n(j['metroMaxM']),
      nearbyMaxM: n(j['nearbyMaxM']),
      nearbyKind: j['nearbyKind'] as String?,
      centerLat: n(j['centerLat']),
      centerLng: n(j['centerLng']),
      radiusM: n(j['radiusM']),
      withPhotos: j['withPhotos'] == true,
      city: (j['city'] ?? '').toString(),
      district: (j['district'] ?? '').toString(),
      microdistrict: (j['microdistrict'] ?? '').toString(),
      quartal: (j['quartal'] ?? '').toString(),
      area: (j['area'] ?? '').toString(),
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
      propertyType: byName(
        PropertyType.values,
        q['propertyType'],
        PropertyType.any,
      ),
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
      totalFloorsMin: n(q['totalFloorsMin']),
      totalFloorsMax: n(q['totalFloorsMax']),
      yearMin: n(q['yearMin']),
      yearMax: n(q['yearMax']),
      areaMin: n(q['areaMin']),
      areaMax: n(q['areaMax']),
      pricePerSqmMin: n(q['pricePerSqmMin']),
      pricePerSqmMax: n(q['pricePerSqmMax']),
      commissionPercentMin: n(q['commissionPercentMin']),
      commissionPercentMax: n(q['commissionPercentMax']),
      priceCurrency:
          (q['priceCurrency']?.isNotEmpty ?? false) ? q['priceCurrency'] : null,
      metroMaxM: n(q['metroMaxM']),
      nearbyMaxM: n(q['nearbyMaxM']),
      nearbyKind:
          (q['nearbyKind']?.isNotEmpty ?? false) ? q['nearbyKind'] : null,
      centerLat: n(q['centerLat']),
      centerLng: n(q['centerLng']),
      radiusM: n(q['radiusM']),
      withPhotos: q['withPhotos'] == 'true',
      city: (q['city'] ?? '').trim(),
      district: (q['district'] ?? '').trim(),
      microdistrict: (q['microdistrict'] ?? '').trim(),
      quartal: (q['quartal'] ?? '').trim(),
      area: (q['area'] ?? '').trim(),
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
    final p = <String, String>{'countries': countries.join(','), 'limit': '50'};
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
    if (maxAgeDays != null && maxAgeDays! > 0)
      p['maxAgeDays'] = maxAgeDays.toString();
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
    if (totalFloorsMin != null) p['totalFloorsMin'] = totalFloorsMin.toString();
    if (totalFloorsMax != null) p['totalFloorsMax'] = totalFloorsMax.toString();
    if (yearMin != null) p['yearMin'] = yearMin.toString();
    if (yearMax != null) p['yearMax'] = yearMax.toString();
    if (areaMin != null) p['areaMin'] = areaMin.toString();
    if (areaMax != null) p['areaMax'] = areaMax.toString();
    if (pricePerSqmMin != null) p['pricePerSqmMin'] = pricePerSqmMin.toString();
    if (pricePerSqmMax != null) p['pricePerSqmMax'] = pricePerSqmMax.toString();
    if (commissionPercentMin != null) {
      p['commissionPercentMin'] = commissionPercentMin.toString();
    }
    if (commissionPercentMax != null) {
      p['commissionPercentMax'] = commissionPercentMax.toString();
    }
    if (priceCurrency != null && priceCurrency!.isNotEmpty) {
      p['priceCurrency'] = priceCurrency!;
    }
    if (metroMaxM != null) p['metroMaxM'] = metroMaxM.toString();
    if (nearbyMaxM != null) p['nearbyMaxM'] = nearbyMaxM.toString();
    if (nearbyKind != null && nearbyKind!.isNotEmpty)
      p['nearbyKind'] = nearbyKind!;
    if (centerLat != null && centerLng != null && radiusM != null) {
      p['centerLat'] = centerLat.toString();
      p['centerLng'] = centerLng.toString();
      p['radiusM'] = radiusM.toString();
    }
    if (withPhotos) p['withPhotos'] = 'true';
    if (city.trim().isNotEmpty) p['city'] = city.trim();
    if (district.trim().isNotEmpty) p['district'] = district.trim();
    if (microdistrict.trim().isNotEmpty)
      p['microdistrict'] = microdistrict.trim();
    if (quartal.trim().isNotEmpty) p['quartal'] = quartal.trim();
    if (area.trim().isNotEmpty) p['area'] = area.trim();
    if (metro.trim().isNotEmpty) p['metro'] = metro.trim();
    if (query.trim().isNotEmpty) p['query'] = query.trim();
    return p;
  }
}

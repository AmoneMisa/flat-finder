import 'dart:convert';

/// Market-price comparison attached by the backend for recent comparable listings.
class MarketComparison {
  final bool goodPrice;
  final num? medianUsd;
  final int comparableCount;

  const MarketComparison({
    required this.goodPrice,
    required this.medianUsd,
    required this.comparableCount,
  });

  factory MarketComparison.fromJson(Map<String, dynamic> j) => MarketComparison(
    goodPrice: j['goodPrice'] == true,
    medianUsd: j['medianUsd'] as num?,
    comparableCount: (j['comparableCount'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'goodPrice': goodPrice,
    'medianUsd': medianUsd,
    'comparableCount': comparableCount,
  };
}

class MoneyAmount {
  final num amount;
  final String? currency;
  final bool approximate;

  const MoneyAmount({
    required this.amount,
    this.currency,
    this.approximate = false,
  });

  factory MoneyAmount.fromJson(Map<String, dynamic> j) => MoneyAmount(
    amount: j['amount'] as num? ?? 0,
    currency: j['currency']?.toString(),
    approximate: j['approximate'] == true,
  );

  Map<String, dynamic> toJson() => {
    'amount': amount,
    'currency': currency,
    if (approximate) 'approximate': true,
  };
}


class NearbyTransportStop {
  final String id;
  final String name;
  final String mode;
  final int distanceM;
  final List<String> routeRefs;

  const NearbyTransportStop({
    required this.id,
    required this.name,
    required this.mode,
    required this.distanceM,
    this.routeRefs = const [],
  });

  factory NearbyTransportStop.fromJson(Map<String, dynamic> j) => NearbyTransportStop(
    id: j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    mode: j['mode']?.toString() ?? '',
    distanceM: (j['distanceM'] as num?)?.round() ?? 0,
    routeRefs: (j['routeRefs'] as List?)?.map((e) => e.toString()).toList() ?? const [],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'mode': mode,
    'distanceM': distanceM,
    'routeRefs': routeRefs,
  };

  String get displayLabel {
    final routes = routeRefs.isEmpty ? '' : ' · ${routeRefs.join(', ')}';
    return '$name$routes · $distanceM m';
  }
}

String? _locationName(dynamic value) {
  if (value == null) return null;
  if (value is Map) {
    for (final key in ['name', 'canonicalName', 'label', 'station', 'value']) {
      final name = _locationName(value[key]);
      if (name != null && name.isNotEmpty) return name;
    }
    return null;
  }
  if (value is Iterable && value is! String) {
    for (final item in value) {
      final name = _locationName(item);
      if (name != null && name.isNotEmpty) return name;
    }
    return null;
  }
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  if (text.startsWith('{') || text.startsWith('[')) {
    try {
      final decoded = jsonDecode(text);
      final name = _locationName(decoded);
      if (name != null && name.isNotEmpty) return name;
    } catch (_) {}
  }
  return text;
}

String _capitalizeFirstLetter(String value) {
  if (value.isEmpty) return value;
  final runes = value.runes.toList();
  for (var i = 0; i < runes.length; i++) {
    final char = String.fromCharCodes([runes[i]]);
    final upper = char.toUpperCase();
    if (upper == char.toLowerCase()) continue;
    if (upper == char) return value;
    return '${String.fromCharCodes(runes.take(i))}$upper${String.fromCharCodes(runes.skip(i + 1))}';
  }
  return value;
}

/// A normalized listing as returned by the backend `/api/listings` endpoint.
class Listing {
  final String id;
  final String source; // olx | telegram | mock
  final String country; // RO | UA | KZ | UZ
  final String title;
  final String propertyType; // flat | house
  final String? dealType; // sale | longRent | shortRent | null (unknown)
  final bool byAgency; // true = real-estate agency, false = private owner
  final num? price;
  final String currency;
  final int? rooms;
  final num? areaSqm;
  final int? floor;
  final int? totalFloors;
  final int? buildingYear;
  final int? bedrooms;
  final String? audience; // women | men | family | null
  final String? contact; // phone or @handle | null
  final String? district; // intra-city district / neighbourhood | null
  final String? metro; // nearest metro/transit station | null
  final List<NearbyTransportStop> nearbyMetro;
  final List<NearbyTransportStop> nearbyTransport;
  final List<String> nearby; // nearby landmarks
  final List<String> nearbyShops; // named shop/mall chains mentioned
  final bool? petsAllowed; // true/false/null (unstated)
  final bool? childrenAllowed; // true/false/null (unstated)
  final bool roomOnly; // renting a single room, not the whole flat
  final bool? deposit; // security deposit required?
  final num? depositAmount; // stated deposit amount, if any
  final bool? commission; // agency commission charged?
  final num? commissionPercent; // stated commission %, if any
  final bool? negotiable; // price open to negotiation?
  final bool? smokingAllowed;
  final bool? newBuilding;
  final bool? communalSeparated; // utilities billed separately from rent?
  final String? condition; // needs_renovation | basic | good | modern | luxury
  final int? bathrooms;
  final String? address;
  final String? residenceComplex; // named residential complex
  final String? kvartal; // city sub-area / quarter
  // Amenity/feature booleans — spec-table rows, same fields the site's
  // UiSpecTable amenities group shows.
  final bool? parking;
  final bool? elevator;
  final bool? furnished;
  final bool? balcony;
  final bool? terrace;
  final bool? privateYard;
  final bool? dishwasher;
  final bool? airConditioner;
  final bool? gas;
  final bool? heating;
  final bool? hotWater;
  final bool? internet;
  final bool? tv;
  final bool? microwave;
  final bool? oven;
  final bool? bidet;
  final bool? walkInCloset;
  final bool? bathtub;
  final bool? shower;
  final bool? euroLayout;
  final bool? cadastral;
  final bool? firstRental;
  final bool potentiallyUnsafe;
  final bool? studentTarget;
  final bool? landlordPresent;
  final String? minLeaseTerm;
  final String? availableFrom;
  final MoneyAmount? utilitiesAmount;
  final MoneyAmount? commissionAmount;
  final MoneyAmount? perPersonPrice;
  final List<String> transitRoutes;
  final String city;
  final double? lat;
  final double? lng;
  final String? photo;
  final List<String> photos;
  final String url;
  final DateTime? createdAt;
  final String description;
  final List<String> tags;
  final MarketComparison? marketComparison;

  /// Stable, source-independent id (the listings table's BIGSERIAL, stamped
  /// onto every row by a DB trigger) used for single-listing share links —
  /// `source`+`id` alone isn't enough since `id` is source-specific.
  final int? publicId;

  Listing({
    required this.id,
    required this.source,
    required this.country,
    required this.title,
    required this.propertyType,
    required this.dealType,
    required this.byAgency,
    required this.price,
    required this.currency,
    required this.rooms,
    required this.areaSqm,
    required this.floor,
    required this.totalFloors,
    required this.buildingYear,
    required this.bedrooms,
    required this.audience,
    required this.contact,
    required this.district,
    required this.metro,
    this.nearbyMetro = const [],
    this.nearbyTransport = const [],
    required this.nearby,
    this.nearbyShops = const [],
    this.petsAllowed,
    this.childrenAllowed,
    this.roomOnly = false,
    this.deposit,
    this.depositAmount,
    this.commission,
    this.commissionPercent,
    this.negotiable,
    this.smokingAllowed,
    this.newBuilding,
    this.communalSeparated,
    this.condition,
    this.bathrooms,
    this.address,
    this.residenceComplex,
    this.kvartal,
    this.parking,
    this.elevator,
    this.furnished,
    this.balcony,
    this.terrace,
    this.privateYard,
    this.dishwasher,
    this.airConditioner,
    this.gas,
    this.heating,
    this.hotWater,
    this.internet,
    this.tv,
    this.microwave,
    this.oven,
    this.bidet,
    this.walkInCloset,
    this.bathtub,
    this.shower,
    this.euroLayout,
    this.cadastral,
    this.firstRental,
    this.potentiallyUnsafe = false,
    this.studentTarget,
    this.landlordPresent,
    this.minLeaseTerm,
    this.availableFrom,
    this.utilitiesAmount,
    this.commissionAmount,
    this.perPersonPrice,
    this.transitRoutes = const [],
    required this.city,
    required this.lat,
    required this.lng,
    required this.photo,
    this.photos = const [],
    required this.url,
    required this.createdAt,
    required this.description,
    required this.tags,
    this.marketComparison,
    this.publicId,
  });

  bool get hasLocation => lat != null && lng != null;

  List<NearbyTransportStop> transportByMode(String mode) => nearbyTransport
      .where((stop) => stop.mode == mode)
      .toList(growable: false);

  String? transportSummary(String mode) {
    final stops = transportByMode(mode);
    if (stops.isEmpty) return null;
    return stops.map((stop) => stop.displayLabel).join(', ');
  }

  factory Listing.fromJson(Map<String, dynamic> j) {
    double? toD(dynamic v) => v == null ? null : (v as num).toDouble();
    final market = j['marketComparison'];
    return Listing(
      id: j['id'].toString(),
      source: j['source'] ?? 'mock',
      country: j['country'] ?? '',
      title: j['title'] ?? 'Untitled',
      propertyType: j['propertyType'] == 'house' ? 'house' : 'flat',
      dealType: j['dealType'] as String?,
      byAgency: j['byAgency'] == true,
      price: j['price'] as num?,
      currency: j['currency'] ?? '',
      rooms: (j['rooms'] as num?)?.toInt(),
      areaSqm: j['areaSqm'] as num?,
      floor: (j['floor'] as num?)?.toInt(),
      totalFloors: (j['totalFloors'] as num?)?.toInt(),
      buildingYear: (j['buildingYear'] as num?)?.toInt(),
      bedrooms: (j['bedrooms'] as num?)?.toInt(),
      audience: j['audience'] as String?,
      contact: j['contact'] as String?,
      district: _locationName(j['district']),
      metro: _locationName(j['metro']),
      nearbyMetro: (j['nearbyMetro'] as List?)
              ?.whereType<Map>()
              .map((e) => NearbyTransportStop.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      nearbyTransport: (j['nearbyTransport'] as List?)
              ?.whereType<Map>()
              .map((e) => NearbyTransportStop.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      nearby:
          (j['nearby'] as List?)
              ?.map((e) => _capitalizeFirstLetter(e.toString()))
              .toList() ??
          const [],
      nearbyShops:
          (j['nearbyShops'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      petsAllowed: j['petsAllowed'] as bool?,
      childrenAllowed: j['childrenAllowed'] as bool?,
      roomOnly: j['roomOnly'] == true,
      deposit: j['deposit'] as bool?,
      depositAmount: j['depositAmount'] as num?,
      commission: j['commission'] as bool?,
      commissionPercent: j['commissionPercent'] as num?,
      negotiable: j['negotiable'] as bool?,
      smokingAllowed: j['smokingAllowed'] as bool?,
      newBuilding: j['newBuilding'] as bool?,
      communalSeparated: j['communalSeparated'] as bool?,
      condition: (j['condition'] ?? j['propertyCondition']) as String?,
      bathrooms: (j['bathrooms'] as num?)?.toInt(),
      address: j['address'] as String?,
      residenceComplex: j['residenceComplex'] as String?,
      kvartal: _locationName(j['kvartal'] ?? j['area']),
      parking: j['parking'] as bool?,
      elevator: j['elevator'] as bool?,
      furnished: j['furnished'] as bool?,
      balcony: j['balcony'] as bool?,
      terrace: j['terrace'] as bool?,
      privateYard: j['privateYard'] as bool?,
      dishwasher: j['dishwasher'] as bool?,
      airConditioner: j['airConditioner'] as bool?,
      gas: j['gas'] as bool?,
      heating: j['heating'] as bool?,
      hotWater: j['hotWater'] as bool?,
      internet: j['internet'] as bool?,
      tv: j['tv'] as bool?,
      microwave: j['microwave'] as bool?,
      oven: j['oven'] as bool?,
      bidet: j['bidet'] as bool?,
      walkInCloset: j['walkInCloset'] as bool?,
      bathtub: j['bathtub'] as bool?,
      shower: j['shower'] as bool?,
      euroLayout: j['euroLayout'] as bool?,
      cadastral: j['cadastral'] as bool?,
      firstRental: j['firstRental'] as bool?,
      potentiallyUnsafe: j['potentiallyUnsafe'] == true,
      studentTarget: j['studentTarget'] as bool?,
      landlordPresent: j['landlordPresent'] as bool?,
      minLeaseTerm: j['minLeaseTerm']?.toString(),
      availableFrom: j['availableFrom']?.toString(),
      utilitiesAmount: j['utilitiesAmount'] is Map
          ? MoneyAmount.fromJson(
              Map<String, dynamic>.from(j['utilitiesAmount'] as Map),
            )
          : null,
      commissionAmount: j['commissionAmount'] is Map
          ? MoneyAmount.fromJson(
              Map<String, dynamic>.from(j['commissionAmount'] as Map),
            )
          : null,
      perPersonPrice: j['perPersonPrice'] is Map
          ? MoneyAmount.fromJson(
              Map<String, dynamic>.from(j['perPersonPrice'] as Map),
            )
          : null,
      transitRoutes:
          (j['transitRoutes'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      city: _locationName(j['city']) ?? '',
      lat: toD(j['lat']),
      lng: toD(j['lng']),
      photo: j['photo'],
      photos:
          (j['photos'] as List?)?.map((e) => e.toString()).toList() ??
          (j['photo'] != null ? [j['photo'].toString()] : const []),
      url: j['url'] ?? '',
      createdAt: j['createdAt'] != null
          ? DateTime.tryParse(j['createdAt'])
          : null,
      description: j['description'] ?? '',
      tags: (j['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      marketComparison: market is Map
          ? MarketComparison.fromJson(Map<String, dynamic>.from(market))
          : null,
      publicId: (j['publicId'] as num?)?.toInt(),
    );
  }

  /// Round-trips through [Listing.fromJson]; used to persist favorites locally.
  Map<String, dynamic> toJson() => {
    'id': id,
    'source': source,
    'country': country,
    'title': title,
    'propertyType': propertyType,
    'dealType': dealType,
    'byAgency': byAgency,
    'price': price,
    'currency': currency,
    'rooms': rooms,
    'areaSqm': areaSqm,
    'floor': floor,
    'totalFloors': totalFloors,
    'buildingYear': buildingYear,
    'bedrooms': bedrooms,
    'audience': audience,
    'contact': contact,
    'district': district,
    'metro': metro,
    'nearbyMetro': nearbyMetro.map((e) => e.toJson()).toList(),
    'nearbyTransport': nearbyTransport.map((e) => e.toJson()).toList(),
    'nearby': nearby,
    'nearbyShops': nearbyShops,
    'petsAllowed': petsAllowed,
    'childrenAllowed': childrenAllowed,
    'roomOnly': roomOnly,
    'deposit': deposit,
    'depositAmount': depositAmount,
    'commission': commission,
    'commissionPercent': commissionPercent,
    'negotiable': negotiable,
    'smokingAllowed': smokingAllowed,
    'newBuilding': newBuilding,
    'communalSeparated': communalSeparated,
    'condition': condition,
    'bathrooms': bathrooms,
    'address': address,
    'residenceComplex': residenceComplex,
    'kvartal': kvartal,
    'parking': parking,
    'elevator': elevator,
    'furnished': furnished,
    'balcony': balcony,
    'terrace': terrace,
    'privateYard': privateYard,
    'dishwasher': dishwasher,
    'airConditioner': airConditioner,
    'gas': gas,
    'heating': heating,
    'hotWater': hotWater,
    'internet': internet,
    'tv': tv,
    'microwave': microwave,
    'oven': oven,
    'bidet': bidet,
    'walkInCloset': walkInCloset,
    'bathtub': bathtub,
    'shower': shower,
    'euroLayout': euroLayout,
    'cadastral': cadastral,
    'firstRental': firstRental,
    'potentiallyUnsafe': potentiallyUnsafe,
    'studentTarget': studentTarget,
    'landlordPresent': landlordPresent,
    'minLeaseTerm': minLeaseTerm,
    'availableFrom': availableFrom,
    if (utilitiesAmount != null) 'utilitiesAmount': utilitiesAmount!.toJson(),
    if (commissionAmount != null)
      'commissionAmount': commissionAmount!.toJson(),
    if (perPersonPrice != null) 'perPersonPrice': perPersonPrice!.toJson(),
    'transitRoutes': transitRoutes,
    'city': city,
    'lat': lat,
    'lng': lng,
    'photo': photo,
    'photos': photos,
    'url': url,
    'createdAt': createdAt?.toIso8601String(),
    'description': description,
    'tags': tags,
    if (marketComparison != null)
      'marketComparison': marketComparison!.toJson(),
    if (publicId != null) 'publicId': publicId,
  };
}

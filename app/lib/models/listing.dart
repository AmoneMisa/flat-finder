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
      district: j['district'] as String?,
      metro: j['metro'] as String?,
      nearby: (j['nearby'] as List?)
              ?.map((e) => _capitalizeFirstLetter(e.toString()))
              .toList() ??
          const [],
      nearbyShops: (j['nearbyShops'] as List?)?.map((e) => e.toString()).toList() ?? const [],
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
      kvartal: (j['kvartal'] ?? j['area']) as String?,
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
      city: j['city'] ?? '',
      lat: toD(j['lat']),
      lng: toD(j['lng']),
      photo: j['photo'],
      photos: (j['photos'] as List?)?.map((e) => e.toString()).toList() ??
          (j['photo'] != null ? [j['photo'].toString()] : const []),
      url: j['url'] ?? '',
      createdAt: j['createdAt'] != null ? DateTime.tryParse(j['createdAt']) : null,
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
        'city': city,
        'lat': lat,
        'lng': lng,
        'photo': photo,
        'photos': photos,
        'url': url,
        'createdAt': createdAt?.toIso8601String(),
        'description': description,
        'tags': tags,
        if (marketComparison != null) 'marketComparison': marketComparison!.toJson(),
        if (publicId != null) 'publicId': publicId,
      };
}
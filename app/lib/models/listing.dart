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
  final bool? petsAllowed; // true/false/null (unstated)
  final bool? childrenAllowed; // true/false/null (unstated)
  final bool roomOnly; // renting a single room, not the whole flat
  final bool? deposit; // security deposit required?
  final num? depositAmount; // stated deposit amount, if any
  final bool? commission; // agency commission charged?
  final num? commissionPercent; // stated commission %, if any
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
    this.petsAllowed,
    this.childrenAllowed,
    this.roomOnly = false,
    this.deposit,
    this.depositAmount,
    this.commission,
    this.commissionPercent,
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
      nearby: (j['nearby'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      petsAllowed: j['petsAllowed'] as bool?,
      childrenAllowed: j['childrenAllowed'] as bool?,
      roomOnly: j['roomOnly'] == true,
      deposit: j['deposit'] as bool?,
      depositAmount: j['depositAmount'] as num?,
      commission: j['commission'] as bool?,
      commissionPercent: j['commissionPercent'] as num?,
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
        'petsAllowed': petsAllowed,
        'childrenAllowed': childrenAllowed,
        'roomOnly': roomOnly,
        'deposit': deposit,
        'depositAmount': depositAmount,
        'commission': commission,
        'commissionPercent': commissionPercent,
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
      };
}

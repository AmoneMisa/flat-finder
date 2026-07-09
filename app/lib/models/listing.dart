/// A normalized listing as returned by the backend `/api/listings` endpoint.
class Listing {
  final String id;
  final String source; // olx | housekg | mock
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
  final String city;
  final double? lat;
  final double? lng;
  final String? photo;
  final String url;
  final DateTime? createdAt;
  final String description;
  final List<String> tags;

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
    required this.city,
    required this.lat,
    required this.lng,
    required this.photo,
    required this.url,
    required this.createdAt,
    required this.description,
    required this.tags,
  });

  bool get hasLocation => lat != null && lng != null;

  factory Listing.fromJson(Map<String, dynamic> j) {
    double? toD(dynamic v) => v == null ? null : (v as num).toDouble();
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
      city: j['city'] ?? '',
      lat: toD(j['lat']),
      lng: toD(j['lng']),
      photo: j['photo'],
      url: j['url'] ?? '',
      createdAt: j['createdAt'] != null ? DateTime.tryParse(j['createdAt']) : null,
      description: j['description'] ?? '',
      tags: (j['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }
}

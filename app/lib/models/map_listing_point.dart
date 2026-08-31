import 'listing.dart';
import 'listing_identity.dart';

/// Compact presentation model matching the backend `mapPoints` contract.
///
/// Map browsing can contain thousands of records. Keeping those records as
/// full [Listing] objects needlessly allocates every details-only field,
/// transport list and preserved raw DTO map. A full Listing is created only
/// when the user taps a point that is not already present in the card results.
class MapListingPoint {
  const MapListingPoint({
    required this.id,
    required this.source,
    required this.country,
    required this.lat,
    required this.lng,
    required this.title,
    required this.currency,
    required this.city,
    required this.propertyType,
    this.price,
    this.publicId,
    this.district,
    this.dealType,
    this.roomOnly = false,
    this.byAgency = false,
    this.rooms,
    this.areaSqm,
    this.photo,
    this.createdAt,
    this.marketMedianUsd,
  });

  final String id;
  final String source;
  final String country;
  final double lat;
  final double lng;
  final String title;
  final num? price;
  final String currency;
  final int? publicId;
  final String city;
  final String? district;
  final String? dealType;
  final bool roomOnly;
  final bool byAgency;
  final String propertyType;
  final num? rooms;
  final num? areaSqm;
  final String? photo;
  final DateTime? createdAt;

  /// Present only when this point was adapted from an already-loaded Listing.
  /// Backend compact map points intentionally do not carry market analytics.
  final num? marketMedianUsd;

  String get key => listingKeyParts(
        source: source,
        country: country,
        id: id,
      );

  factory MapListingPoint.fromJson(Map<String, dynamic> json) {
    final lat = (json['lat'] as num?)?.toDouble();
    final lng = (json['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) {
      throw const FormatException('map point requires finite coordinates');
    }
    return MapListingPoint(
      id: json['id']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
      country: (json['country']?.toString() ?? '').toUpperCase(),
      lat: lat,
      lng: lng,
      title: json['title']?.toString() ?? '',
      price: json['price'] as num?,
      currency: json['currency']?.toString() ?? '',
      publicId: (json['publicId'] as num?)?.toInt(),
      city: json['city']?.toString() ?? '',
      district: json['district']?.toString(),
      dealType: json['dealType']?.toString(),
      roomOnly: json['roomOnly'] == true,
      byAgency: json['byAgency'] == true,
      propertyType: json['propertyType']?.toString() ?? 'flat',
      rooms: json['rooms'] as num?,
      areaSqm: json['areaSqm'] as num?,
      photo: json['photo']?.toString(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    );
  }

  factory MapListingPoint.fromListing(Listing listing) {
    if (!listing.hasLocation) {
      throw ArgumentError.value(listing.id, 'listing', 'location is required');
    }
    return MapListingPoint(
      id: listing.id,
      source: listing.source,
      country: listing.country,
      lat: listing.lat!,
      lng: listing.lng!,
      title: listing.title,
      price: listing.price,
      currency: listing.currency,
      publicId: listing.publicId,
      city: listing.city,
      district: listing.district,
      dealType: listing.dealType,
      roomOnly: listing.roomOnly,
      byAgency: listing.byAgency,
      propertyType: listing.propertyType,
      rooms: listing.rooms,
      areaSqm: listing.areaSqm,
      photo: listing.photo ??
          (listing.photos.isNotEmpty ? listing.photos.first : null),
      createdAt: listing.createdAt,
      marketMedianUsd: listing.marketComparison?.medianUsd,
    );
  }

  /// Creates a single lightweight full-model fallback for the existing preview
  /// widget. Normal card-page results are preferred by key before this is used.
  Listing toPreviewListing() => Listing.fromJson({
        'id': id,
        'source': source,
        'country': country,
        'lat': lat,
        'lng': lng,
        'title': title,
        'price': price,
        'currency': currency,
        'publicId': publicId,
        'city': city,
        'district': district,
        'dealType': dealType,
        'roomOnly': roomOnly,
        'byAgency': byAgency,
        'propertyType': propertyType,
        'rooms': rooms,
        'areaSqm': areaSqm,
        'photo': photo,
        'createdAt': createdAt?.toIso8601String(),
        if (marketMedianUsd != null)
          'marketComparison': {
            'medianUsd': marketMedianUsd,
            'goodPrice': false,
            'comparableCount': 0,
          },
      });
}

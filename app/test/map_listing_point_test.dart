import 'package:flutter_test/flutter_test.dart';

import 'package:flat_finder/models/listing.dart';
import 'package:flat_finder/models/map_listing_point.dart';

void main() {
  test('parses backend compact map point without full listing DTO', () {
    final point = MapListingPoint.fromJson({
      'id': 'abc',
      'source': 'olx',
      'country': 'uz',
      'lat': 41.31,
      'lng': 69.28,
      'title': 'Compact flat',
      'price': 4500000,
      'currency': 'UZS',
      'publicId': 42,
      'city': 'Tashkent',
      'district': 'Chilanzar',
      'dealType': 'longRent',
      'roomOnly': false,
      'byAgency': true,
      'propertyType': 'flat',
      'rooms': 2,
      'areaSqm': 54,
      'photo': 'https://example.test/photo.jpg',
      'createdAt': '2026-08-31T08:00:00.000Z',
    });

    expect(point.key, 'olx:UZ:abc');
    expect(point.lat, 41.31);
    expect(point.publicId, 42);
    expect(point.marketMedianUsd, isNull);
  });

  test('adapts loaded listing and creates one preview fallback', () {
    final listing = Listing.fromJson({
      'id': 'same',
      'source': 'telegram',
      'country': 'UA',
      'lat': 49.99,
      'lng': 36.23,
      'title': 'Full listing',
      'price': 12000,
      'currency': 'UAH',
      'city': 'Kharkiv',
      'propertyType': 'flat',
      'photo': 'https://example.test/full.jpg',
      'marketComparison': {
        'medianUsd': 400,
        'goodPrice': true,
        'comparableCount': 10,
      },
      'futureBackendField': {'preserve': true},
    });

    final point = MapListingPoint.fromListing(listing);
    expect(point.key, 'telegram:UA:same');
    expect(point.marketMedianUsd, 400);

    final preview = point.toPreviewListing();
    expect(preview.id, listing.id);
    expect(preview.source, listing.source);
    expect(preview.country, listing.country);
    expect(preview.marketComparison?.medianUsd, 400);
    expect(preview.photo, 'https://example.test/full.jpg');
  });

  test('rejects a full listing without coordinates', () {
    final listing = Listing.fromJson({
      'id': 'no-geo',
      'source': 'olx',
      'country': 'UZ',
      'title': 'No location',
      'currency': 'UZS',
      'city': 'Tashkent',
      'propertyType': 'flat',
    });

    expect(() => MapListingPoint.fromListing(listing), throwsArgumentError);
  });
}

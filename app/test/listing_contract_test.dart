import 'package:flutter_test/flutter_test.dart';
import 'package:flat_finder/models/listing.dart';

void main() {
  Map<String, dynamic> listingJson() => {
    'id': 'olx-42',
    'source': 'olx',
    'country': 'UZ',
    'title': 'Tashkent flat',
    'propertyType': 'flat',
    'dealType': 'longRent',
    'byAgency': false,
    'price': 500,
    'currency': 'USD',
    'rooms': 2,
    'areaSqm': 55,
    'city': 'Tashkent',
    'lat': 41.31,
    'lng': 69.25,
    'photos': <String>[],
    'url': 'https://example.test/listing/42',
    'description': 'Flat description',
    'tags': <String>[],
  };

  test('bus metadata survives Flutter parse and persistence round trip', () {
    final json = listingJson()
      ..['nearbyTransport'] = [
        {
          'id': 'stop-1',
          'name': 'Amir Temur',
          'mode': 'bus',
          'distanceM': 180,
          'routeRefs': ['17', '24'],
          'geoEntityId': 'uz:tashkent:bus:stop-1',
          'osm': {'type': 'node', 'id': 12345},
          'source': 'geo-catalog',
        },
      ];

    final listing = Listing.fromJson(json);
    expect(listing.transportSummary('bus'), 'Amir Temur · 17, 24 · 180 m');

    final persisted = listing.toJson();
    final stop = (persisted['nearbyTransport'] as List).single as Map;
    expect(stop['geoEntityId'], 'uz:tashkent:bus:stop-1');
    expect(stop['source'], 'geo-catalog');
    expect((stop['osm'] as Map)['id'], 12345);

    final restored = Listing.fromJson(persisted);
    expect(restored.transportByMode('bus').single.routeRefs, ['17', '24']);
  });

  test('unknown backend fields survive local Listing.toJson', () {
    final json = listingJson()
      ..['region'] = 'Tashkent'
      ..['locationAccuracyM'] = 25
      ..['locationSource'] = 'coordinates'
      ..['vision'] = {
        'provider': 'test',
        'derivedFields': ['parking'],
      };

    final persisted = Listing.fromJson(json).toJson();

    expect(persisted['region'], 'Tashkent');
    expect(persisted['locationAccuracyM'], 25);
    expect(persisted['locationSource'], 'coordinates');
    expect((persisted['vision'] as Map)['provider'], 'test');
  });

  test('minimum lease term accepts legacy backend key and writes canonical key', () {
    final json = listingJson()..['minRentTerm'] = '6 months';
    final listing = Listing.fromJson(json);

    expect(listing.minLeaseTerm, '6 months');
    expect(listing.toJson()['minLeaseTerm'], '6 months');
  });

  test('market comparison keeps priceUsd and priceRatio', () {
    final json = listingJson()
      ..['marketComparison'] = {
        'goodPrice': true,
        'medianUsd': 600,
        'comparableCount': 12,
        'priceUsd': 500,
        'priceRatio': 0.8333,
      };

    final listing = Listing.fromJson(json);
    expect(listing.marketComparison?.priceUsd, 500);
    expect(listing.marketComparison?.priceRatio, 0.8333);

    final persisted = listing.toJson()['marketComparison'] as Map;
    expect(persisted['priceUsd'], 500);
    expect(persisted['priceRatio'], 0.8333);
  });
}

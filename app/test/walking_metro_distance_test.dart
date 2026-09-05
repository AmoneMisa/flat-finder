import 'package:flat_finder/models/listing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> listingJson() => {
        'id': 'olx-walk-1',
        'source': 'olx',
        'country': 'UZ',
        'title': 'Tashkent flat',
        'propertyType': 'flat',
        'dealType': 'longRent',
        'byAgency': false,
        'price': 500,
        'currency': 'USD',
        'city': 'Tashkent',
        'metro': 'Ming Orik',
        'metroWalkingDistanceM': 980,
        'metroWalkingDurationMin': 13,
        'nearbyMetro': [
          {
            'id': 'metro-ming-orik',
            'name': 'Ming Orik',
            'mode': 'metro',
            'distanceM': 900,
            'walkingDistanceM': 980,
            'walkingDurationMin': 13,
            'walkingSource': 'valhalla',
            'routeRefs': ['chilonzor'],
          },
        ],
        'nearby': <String>[],
        'nearbyTransport': <Map<String, dynamic>>[],
        'lat': 41.31,
        'lng': 69.28,
        'photos': <String>[],
        'url': 'https://example.test/listing/walk-1',
        'description': 'Flat description',
        'tags': <String>[],
      };

  test('walking metro metrics survive parse and persistence round trip', () {
    final listing = Listing.fromJson(listingJson());

    expect(listing.metroWalkingDistanceM, 980);
    expect(listing.metroWalkingDurationMin, 13);
    expect(listing.nearbyMetro.single.distanceM, 900);
    expect(listing.nearbyMetro.single.walkingDistanceM, 980);
    expect(listing.nearbyMetro.single.walkingDurationMin, 13);
    expect(listing.nearbyMetro.single.walkingSource, 'valhalla');
    expect(
      listing.nearbyMetro.single.displayLabel,
      'Ming Orik · chilonzor · 🚶 980 m · 13 min',
    );

    final restored = Listing.fromJson(listing.toJson());
    expect(restored.metroWalkingDistanceM, 980);
    expect(restored.metroWalkingDurationMin, 13);
    expect(restored.nearbyMetro.single.walkingDistanceM, 980);
    expect(restored.nearbyMetro.single.walkingDurationMin, 13);
    expect(restored.nearbyMetro.single.walkingSource, 'valhalla');
  });

  test('straight-line distance remains the fallback without routing data', () {
    final json = listingJson()
      ..remove('metroWalkingDistanceM')
      ..remove('metroWalkingDurationMin')
      ..['nearbyMetro'] = [
        {
          'id': 'metro-ming-orik',
          'name': 'Ming Orik',
          'mode': 'metro',
          'distanceM': 900,
          'routeRefs': ['chilonzor'],
        },
      ];

    final listing = Listing.fromJson(json);
    expect(listing.metroWalkingDistanceM, isNull);
    expect(listing.metroWalkingDurationMin, isNull);
    expect(
      listing.nearbyMetro.single.displayLabel,
      'Ming Orik · chilonzor · 900 m',
    );
  });
}

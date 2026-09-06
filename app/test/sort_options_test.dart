import 'package:flutter_test/flutter_test.dart';

import '../lib/models/filters.dart';
import '../lib/models/listing.dart';
import '../lib/utils/sort.dart';

Listing _listing(
  String id, {
  required num price,
  required String currency,
  int? metroWalkingDistanceM,
  List<Map<String, dynamic>> nearbyMetro = const [],
}) =>
    Listing.fromJson({
      'id': id,
      'source': 'olx',
      'country': 'UZ',
      'title': id,
      'propertyType': 'flat',
      'price': price,
      'currency': currency,
      'city': 'Tashkent',
      'url': 'https://example.test/$id',
      'description': '',
      'tags': <String>[],
      'metroWalkingDistanceM': metroWalkingDistanceM,
      'nearbyMetro': nearbyMetro,
    });

void main() {
  test('title ordering is not offered as a sort', () {
    // The sort menu is built from SortBy.values, so absence here is what keeps
    // the app off the backend's general search path.
    expect(
      SortBy.values.map((v) => v.name),
      isNot(anyElement(anyOf('titleAsc', 'titleDesc'))),
    );
  });

  test('a stored or shared title sort decodes to the server order', () {
    expect(
      Filters.fromJson(const {'sort': 'titleAsc'}).sort,
      SortBy.relevance,
      reason: 'saved presets from an older build must stay loadable',
    );
    expect(
      Filters.fromQueryParams(const {'sort': 'titleDesc'}).sort,
      SortBy.relevance,
      reason: 'shared links from an older build must stay openable',
    );
  });

  test('the remaining sorts still round-trip', () {
    for (final sort in SortBy.values) {
      final restored = Filters.fromJson(Filters(sort: sort).toJson()).sort;
      expect(restored, sort);
    }
  });

  test('mixed native currencies preserve server price order without FX', () {
    final serverOrder = [
      _listing('usd', price: 700, currency: 'USD'),
      _listing('eur', price: 600, currency: 'EUR'),
    ];

    final sorted = sortListings(serverOrder, SortBy.priceAsc);

    expect(sorted.map((item) => item.id).toList(), ['usd', 'eur']);
  });

  test('price sort normalizes currencies when complete FX rates exist', () {
    final rows = [
      _listing('eur', price: 600, currency: 'EUR'),
      _listing('usd', price: 650, currency: 'USD'),
    ];

    final sorted = sortListings(
      rows,
      SortBy.priceAsc,
      rates: const {'USD': 1, 'EUR': 0.8},
      displayCurrency: 'USD',
    );

    // 650 USD < 600 EUR / 0.8 = 750 USD.
    expect(sorted.map((item) => item.id).toList(), ['usd', 'eur']);
  });

  test('metro sort uses walking distance instead of city-center proxy', () {
    final rows = [
      _listing(
        'far-walk',
        price: 1,
        currency: 'USD',
        metroWalkingDistanceM: 900,
      ),
      _listing(
        'near-walk',
        price: 1,
        currency: 'USD',
        nearbyMetro: const [
          {
            'id': 'metro:novza',
            'name': 'Novza',
            'mode': 'metro',
            'distanceM': 350,
            'walkingDistanceM': 420,
          },
        ],
      ),
    ];

    final sorted = sortListings(rows, SortBy.distanceMetro);

    expect(sorted.map((item) => item.id).toList(), ['near-walk', 'far-walk']);
  });
}

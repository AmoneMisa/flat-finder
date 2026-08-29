import 'package:flutter_test/flutter_test.dart';

import 'package:flat_finder/models/filters.dart';
import 'package:flat_finder/models/listing.dart';
import 'package:flat_finder/models/search_statistics.dart';
import 'package:flat_finder/utils/format.dart';

void main() {
  test('filters preserve user selections across JSON round-trip', () {
    final original = Filters(
      countries: {'UA', 'UZ'},
      sources: {'telegram'},
      propertyType: PropertyType.flat,
      dealType: DealType.longRent,
      agency: AgencyFilter.owner,
      audience: Audience.family,
      priceMin: 300,
      priceMax: 900,
      city: 'Tashkent',
      district: 'Chilonzor',
      query: 'metro',
      pets: true,
      children: true,
      maxAgeDays: 7,
      sort: SortBy.priceAsc,
    );

    final restored = Filters.fromJson(original.toJson());

    expect(restored.countries, {'UA'});
    expect(restored.sources, {'telegram'});
    expect(restored.propertyType, PropertyType.flat);
    expect(restored.dealType, DealType.longRent);
    expect(restored.agency, AgencyFilter.owner);
    expect(restored.audience, Audience.family);
    expect(restored.priceMin, 300);
    expect(restored.priceMax, 900);
    expect(restored.city, 'Tashkent');
    expect(restored.district, 'Chilonzor');
    expect(restored.query, 'metro');
    expect(restored.pets, isTrue);
    expect(restored.children, isTrue);
    expect(restored.maxAgeDays, 7);
    expect(restored.sort, SortBy.priceAsc);
  });

  test('query params contain only server-side filters', () {
    final filters = Filters(
      countries: {'UZ'},
      sources: {'telegram'},
      dealType: DealType.longRent,
      priceMax: 800,
      priceTolerance: 50,
      city: 'Tashkent',
      pets: true,
      sort: SortBy.priceDesc,
    );

    final params = filters.toQueryParams();

    expect(params['countries'], 'UZ');
    expect(params['sources'], 'telegram');
    expect(params['dealType'], 'longRent');
    expect(params['priceMax'], '800');
    expect(params['priceTolerance'], '50');
    expect(params['city'], 'Tashkent');
    expect(params['pets'], 'true');
    expect(params.containsKey('sort'), isFalse);
  });

  test('nearby labels capitalize the first letter on the frontend', () {
    final listing = Listing.fromJson({
      'id': '1',
      'nearby': ['рынок', 'больница', '#юнусабад -19', 'Vosiq School'],
    });

    expect(listing.nearby, [
      'Рынок',
      'Больница',
      '#Юнусабад -19',
      'Vosiq School',
    ]);
  });

  test('map pin keeps half-thousands instead of rounding 2500 to 3K', () {
    final listing = Listing.fromJson({
      'id': '2500',
      'price': 2500,
      'currency': 'UAH',
    });

    expect(pinPriceLabel(listing), '₴2.5K');
  });

  test('country metadata parses structured sub-city filter options', () {
    final country = Country.fromJson({
      'code': 'UZ',
      'name': 'Uzbekistan',
      'locations': {
        'Tashkent': {
          'districts': ['Chilanzar'],
          'microdistricts': ['Chilanzar-10'],
          'quartals': ['Beshagach'],
          'areas': ['Tashkent City'],
        },
      },
    });

    expect(country.locations['Tashkent']!.microdistricts, ['Chilanzar-10']);
    expect(country.locations['Tashkent']!.quartals, ['Beshagach']);
    expect(country.locations['Tashkent']!.areas, ['Tashkent City']);
  });

  test('statistics parse the complete web graphics contract', () {
    final stats = SearchStatistics.fromJson({
      'total': 10,
      'rawTotal': 14,
      'priceBandsByDeal': {
        'longRent': [
          {'key': 'green', 'count': 3},
        ],
      },
      'priceBandSamplesByDeal': {'longRent': 9},
      'activity': [
        {'date': '2026-08-29', 'count': 4},
      ],
      'quality': {'duplicatesRejected': 4, 'suspectedFake': 1},
      'geographiesByDeal': {
        'longRent': {
          'district': [
            {'label': 'Chilanzar', 'count': 5, 'priceCount': 4},
          ],
        },
      },
    });

    expect(stats.rawTotal, 14);
    expect(stats.priceBandsByDeal['longRent']!.single.count, 3);
    expect(stats.activity.single.count, 4);
    expect(stats.quality.duplicatesRejected, 4);
    expect(
      stats.geographiesByDeal['longRent']!['district']!.single.label,
      'Chilanzar',
    );
  });
}

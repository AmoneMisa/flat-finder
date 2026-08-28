import 'package:flutter_test/flutter_test.dart';

import 'package:flat_finder/models/filters.dart';
import 'package:flat_finder/models/listing.dart';

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

    expect(restored.countries, {'UA', 'UZ'});
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

    expect(listing.nearby, ['Рынок', 'Больница', '#Юнусабад -19', 'Vosiq School']);
  });
}
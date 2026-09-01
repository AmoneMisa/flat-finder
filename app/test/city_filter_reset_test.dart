import 'package:flutter_test/flutter_test.dart';
import 'package:flat_finder/models/filters.dart';

void main() {
  group('city change reset contract', () {
    test('keeps country and deal type while resetting every other filter', () {
      final before = Filters(
        countries: {'UZ'},
        sources: {'olx'},
        customSources: ['https://example.com/feed'],
        propertyType: PropertyType.house,
        dealType: DealType.longRent,
        agency: AgencyFilter.owner,
        audience: Audience.family,
        priceMin: 300,
        priceMax: 900,
        priceTolerance: 100,
        roomsMin: 2,
        roomsMax: 4,
        bedroomsMin: 1,
        bedroomsMax: 3,
        floorMin: 2,
        floorMax: 8,
        totalFloorsMin: 5,
        totalFloorsMax: 12,
        yearMin: 2010,
        yearMax: 2026,
        areaMin: 50,
        areaMax: 120,
        pricePerSqmMin: 5,
        pricePerSqmMax: 25,
        commissionPercentMin: 1,
        commissionPercentMax: 5,
        priceCurrency: 'USD',
        metroMaxM: 800,
        nearbyMaxM: 1200,
        nearbyKind: 'park',
        centerLat: 41.31,
        centerLng: 69.28,
        radiusM: 3000,
        withPhotos: true,
        city: 'Tashkent',
        district: 'Yunusabad',
        microdistrict: '4-mavze',
        quartal: 'Q-1',
        area: 'Center',
        metro: 'Minor',
        query: 'balcony',
        pets: true,
        children: true,
        amenities: {'parking', 'internet'},
        noElevator: true,
        noDeposit: true,
        communalIncluded: true,
        noCommission: true,
        maxAgeDays: 3,
        sort: SortBy.priceAsc,
      );

      final after = before.copyWith(city: 'Samarkand');

      expect(after.countries, {'UZ'});
      expect(after.city, 'Samarkand');
      expect(after.dealType, DealType.longRent);

      expect(after.sources, kAllSources.toSet());
      expect(after.customSources, isEmpty);
      expect(after.propertyType, PropertyType.any);
      expect(after.agency, AgencyFilter.any);
      expect(after.audience, Audience.any);
      expect(after.priceMin, isNull);
      expect(after.priceMax, isNull);
      expect(after.priceTolerance, isNull);
      expect(after.roomsMin, isNull);
      expect(after.roomsMax, isNull);
      expect(after.bedroomsMin, isNull);
      expect(after.bedroomsMax, isNull);
      expect(after.floorMin, isNull);
      expect(after.floorMax, isNull);
      expect(after.totalFloorsMin, isNull);
      expect(after.totalFloorsMax, isNull);
      expect(after.yearMin, isNull);
      expect(after.yearMax, isNull);
      expect(after.areaMin, isNull);
      expect(after.areaMax, isNull);
      expect(after.pricePerSqmMin, isNull);
      expect(after.pricePerSqmMax, isNull);
      expect(after.commissionPercentMin, isNull);
      expect(after.commissionPercentMax, isNull);
      expect(after.priceCurrency, isNull);
      expect(after.metroMaxM, isNull);
      expect(after.nearbyMaxM, isNull);
      expect(after.nearbyKind, isNull);
      expect(after.centerLat, isNull);
      expect(after.centerLng, isNull);
      expect(after.radiusM, isNull);
      expect(after.withPhotos, isFalse);
      expect(after.district, isEmpty);
      expect(after.microdistrict, isEmpty);
      expect(after.quartal, isEmpty);
      expect(after.area, isEmpty);
      expect(after.metro, isEmpty);
      expect(after.query, isEmpty);
      expect(after.pets, isFalse);
      expect(after.children, isFalse);
      expect(after.amenities, isEmpty);
      expect(after.noElevator, isFalse);
      expect(after.noDeposit, isFalse);
      expect(after.communalIncluded, isFalse);
      expect(after.noCommission, isFalse);
      expect(after.maxAgeDays, isNull);
      expect(after.sort, SortBy.relevance);
    });

    test('keeps room-rent deal semantics across a city change', () {
      final before = Filters(
        countries: {'UZ'},
        city: 'Tashkent',
        dealType: DealType.longRent,
        roomOnly: true,
        priceMax: 500,
        agency: AgencyFilter.owner,
      );

      final after = before.copyWith(city: 'Samarkand');

      expect(after.countries, {'UZ'});
      expect(after.city, 'Samarkand');
      expect(after.dealType, DealType.longRent);
      expect(after.roomOnly, isTrue);
      expect(after.priceMax, isNull);
      expect(after.agency, AgencyFilter.any);
    });

    test('changing country and clearing city does not reset unrelated filters', () {
      final before = Filters(
        countries: {'UZ'},
        city: 'Tashkent',
        dealType: DealType.sale,
        priceMax: 120000,
        propertyType: PropertyType.flat,
      );

      final after = before.copyWith(countries: {'KZ'}, city: '');

      expect(after.countries, {'KZ'});
      expect(after.city, isEmpty);
      expect(after.dealType, DealType.sale);
      expect(after.priceMax, 120000);
      expect(after.propertyType, PropertyType.flat);
    });
  });
}

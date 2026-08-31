import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/models/filters.dart';
import '../lib/models/listing.dart';
import '../lib/models/listing_identity.dart';
import '../lib/services/api_service.dart';
import '../lib/state/app_state.dart';
import '../lib/state/favorites.dart';
import '../lib/state/hidden.dart';
import '../lib/state/history.dart';
import '../lib/state/sorted.dart';

Listing listing({
  required String source,
  required String country,
  required String id,
  String city = 'Tashkent',
  String? title,
}) => Listing.fromJson({
  'id': id,
  'source': source,
  'country': country,
  'title': title ?? '$source $country $id',
  'propertyType': 'flat',
  'currency': 'USD',
  'city': city,
  'url': 'https://example.test/$source/$country/$id',
  'description': '',
  'tags': <String>[],
});

class ControlledApi extends ApiService {
  ControlledApi() : super(baseUrl: 'http://test.invalid');

  final forceResult = Completer<ListingsResult>();
  final searchResult = Completer<ListingsResult>();
  ListingsResult? pageResult;

  @override
  Future<ListingsResult> fetchListings(
    Filters filters, {
    bool force = false,
    String? cursor,
  }) {
    if (cursor != null) {
      return Future.value(
        pageResult ?? ListingsResult(const [], const [], const []),
      );
    }
    return force ? forceResult.future : searchResult.future;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('stable listing identity', () {
    test('source and country are part of the key', () {
      final uzOlx = listing(source: 'olx', country: 'UZ', id: '42');
      final kzOlx = listing(source: 'olx', country: 'KZ', id: '42');
      final uzTg = listing(source: 'telegram', country: 'UZ', id: '42');

      expect(listingKey(uzOlx), 'olx:UZ:42');
      expect(sameListing(uzOlx, kzOlx), isFalse);
      expect(sameListing(uzOlx, uzTg), isFalse);
    });

    test('favorites, hidden, history and sorted do not collide on bare id', () async {
      final a = listing(source: 'olx', country: 'UZ', id: '42');
      final b = listing(source: 'olx', country: 'KZ', id: '42');
      final c = listing(source: 'telegram', country: 'UZ', id: '42');

      final favorites = FavoritesState();
      await favorites.toggle(a);
      expect(favorites.isFavorite(a), isTrue);
      expect(favorites.isFavorite(b), isFalse);
      expect(favorites.isFavorite(c), isFalse);

      final hidden = HiddenState();
      await hidden.toggle(b);
      expect(hidden.isHidden(a), isFalse);
      expect(hidden.isHidden(b), isTrue);
      expect(hidden.isHidden(c), isFalse);

      final history = HistoryState();
      await history.record(c);
      expect(history.isViewed(a), isFalse);
      expect(history.isViewed(b), isFalse);
      expect(history.isViewed(c), isTrue);

      final sorted = SortedState();
      await sorted.add(
        a,
        collectionId: 'test',
        collectionTitle: 'Test',
      );
      await sorted.add(
        b,
        collectionId: 'test',
        collectionTitle: 'Test',
      );
      expect(sorted.contains(a), isTrue);
      expect(sorted.contains(b), isTrue);
      expect(sorted.contains(c), isFalse);
      expect(sorted.collections.single.items, hasLength(2));

      await sorted.remove(a, collectionId: 'test');
      expect(sorted.contains(a), isFalse);
      expect(sorted.contains(b), isTrue);
    });

    test('legacy viewed ids migrate only identities recoverable from rich history', () async {
      final known = listing(source: 'olx', country: 'UZ', id: '42');
      final collision = listing(source: 'olx', country: 'KZ', id: '42');
      SharedPreferences.setMockInitialValues({
        'history': jsonEncode([known.toJson()]),
        'viewed_ids': jsonEncode(['42', 'orphan-id']),
      });

      final history = HistoryState();
      await history.load();

      expect(history.isViewed(known), isTrue);
      expect(history.isViewed(collision), isFalse);
      expect(
        (await SharedPreferences.getInstance()).getString('viewed_ids'),
        isNull,
      );
    });
  });

  group('filter update integrity', () {
    test('controls that omit hidden fields preserve radius and price tolerance', () {
      final state = AppState(ControlledApi());
      state.filters = Filters(
        countries: {'UZ'},
        city: 'Tashkent',
        priceMin: 500,
        priceMax: 1000,
        priceTolerance: 75,
        centerLat: 41.31,
        centerLng: 69.28,
        radiusM: 5000,
      );

      final sheetLikeUpdate = Filters(
        countries: {'UZ'},
        city: 'Tashkent',
        priceMin: 500,
        priceMax: 1000,
        agency: AgencyFilter.owner,
      );

      expect(state.updateFilters(sheetLikeUpdate), isTrue);
      expect(state.filters.centerLat, 41.31);
      expect(state.filters.centerLng, 69.28);
      expect(state.filters.radiusM, 5000);
      expect(state.filters.priceTolerance, 75);
      expect(state.filters.agency, AgencyFilter.owner);
    });

    test('changing geography clears stale radius and changing price clears tolerance', () {
      final state = AppState(ControlledApi());
      state.filters = Filters(
        countries: {'UZ'},
        city: 'Tashkent',
        priceMin: 500,
        priceMax: 1000,
        priceTolerance: 75,
        centerLat: 41.31,
        centerLng: 69.28,
        radiusM: 5000,
      );

      state.updateFilters(state.filters.copyWith(city: 'Chirchiq'));
      expect(state.filters.centerLat, isNull);
      expect(state.filters.centerLng, isNull);
      expect(state.filters.radiusM, isNull);
      expect(state.filters.priceTolerance, 75);

      state.updateFilters(state.filters.copyWith(priceMax: 1200));
      expect(state.filters.priceTolerance, isNull);
    });

    test('identical effective payload is a no-op', () {
      final state = AppState(ControlledApi());
      state.filters = Filters(countries: {'UZ'}, city: 'Tashkent');
      expect(state.updateFilters(Filters(countries: {'UZ'}, city: 'Tashkent')), isFalse);
    });
  });

  group('request ordering', () {
    test('stale reload-all response cannot overwrite a newer filtered search', () async {
      final api = ControlledApi();
      final state = AppState(api)
        ..filters = Filters(countries: {'RO'}, city: 'Bucharest');

      final stale = listing(
        source: 'olx',
        country: 'RO',
        id: 'old',
        city: 'Bucharest',
      );
      final fresh = listing(
        source: 'olx',
        country: 'RO',
        id: 'new',
        city: 'Bucharest',
      );

      final reloadFuture = state.reloadAll();
      state.updateFilters(state.filters.copyWith(query: 'two rooms'));
      final searchFuture = state.search();

      api.searchResult.complete(
        ListingsResult([fresh], const [], const [], total: 1),
      );
      await searchFuture;
      expect(state.listings.single.id, 'new');

      api.forceResult.complete(
        ListingsResult([stale], const [], const [], total: 1),
      );
      await reloadFuture;

      expect(state.listings.single.id, 'new');
      expect(state.loading, isFalse);
    });

    test('pagination dedupe keeps same source id from another country', () async {
      final api = ControlledApi();
      final state = AppState(api)
        ..filters = Filters(countries: {'UZ', 'KZ'});
      final uz = listing(source: 'olx', country: 'UZ', id: '42');
      final kz = listing(source: 'olx', country: 'KZ', id: '42');
      state.listings = [uz];
      state.nextCursor = 'next';
      api.pageResult = ListingsResult(
        [uz, kz],
        const [],
        const [],
        total: 2,
      );

      await state.loadMore();

      expect(state.listings.map(listingKey).toSet(), {
        'olx:UZ:42',
        'olx:KZ:42',
      });
    });
  });
}

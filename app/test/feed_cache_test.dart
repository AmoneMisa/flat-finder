import 'dart:async';

import 'package:flat_finder/models/filters.dart';
import 'package:flat_finder/models/listing.dart';
import 'package:flat_finder/models/map_listing_point.dart';
import 'package:flat_finder/services/api_service.dart';
import 'package:flat_finder/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Listing _listing(String id, {String city = 'Tashkent'}) => Listing.fromJson({
  'id': id,
  'source': 'olx',
  'country': 'UZ',
  'title': 'listing $id',
  'propertyType': 'flat',
  'currency': 'USD',
  'city': city,
  'url': 'https://example.test/olx/UZ/$id',
  'description': '',
  'tags': <String>[],
});

MapListingPoint _point(String id, {String city = 'Tashkent'}) =>
    MapListingPoint(
      id: id,
      source: 'olx',
      country: 'UZ',
      lat: 41.31,
      lng: 69.28,
      title: 'listing $id',
      currency: 'USD',
      city: city,
      propertyType: 'flat',
    );

/// Hands out one Completer per call, in order, so a test can control exactly
/// which response answers which search -- unlike the shared single-Completer
/// double in state_correctness_test.dart, which only needs one call in flight
/// at a time.
class _QueueApi extends ApiService {
  _QueueApi() : super(baseUrl: 'http://test.invalid');

  final List<Completer<ListingsResult>> _listingsQueue = [];
  final List<Completer<List<MapListingPoint>>> _mapQueue = [];
  int listingsCalls = 0;
  int mapCalls = 0;

  Completer<ListingsResult> queueListings() {
    final c = Completer<ListingsResult>();
    _listingsQueue.add(c);
    return c;
  }

  Completer<List<MapListingPoint>> queueMap() {
    final c = Completer<List<MapListingPoint>>();
    _mapQueue.add(c);
    return c;
  }

  @override
  Future<ListingsResult> fetchListings(
    Filters filters, {
    bool force = false,
    String? cursor,
  }) {
    listingsCalls++;
    if (_listingsQueue.isEmpty) {
      return Future.value(ListingsResult(const [], const [], const []));
    }
    return _listingsQueue.removeAt(0).future;
  }

  @override
  Future<List<MapListingPoint>> fetchMapListings(Filters filters) {
    mapCalls++;
    if (_mapQueue.isEmpty) return Future.value(const <MapListingPoint>[]);
    return _mapQueue.removeAt(0).future;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('listings cache', () {
    test(
      're-visiting a filter combination paints from cache before the network resolves',
      () async {
        final api = _QueueApi();
        final state = AppState(api)
          ..filters = Filters(countries: {'UZ'}, city: 'Tashkent');

        final first = api.queueListings();
        final searchA = state.search();
        first.complete(
          ListingsResult([_listing('a')], const [], const [], total: 1),
        );
        await searchA;
        expect(state.listings.single.id, 'a');

        state.updateFilters(state.filters.copyWith(city: 'Samarkand'));
        final second = api.queueListings();
        final searchB = state.search();
        second.complete(
          ListingsResult([_listing('b')], const [], const [], total: 1),
        );
        await searchB;
        expect(state.listings.single.id, 'b');

        // Back to the first combination: the network has not been asked
        // anything yet, but the cached page is already on screen.
        state.updateFilters(state.filters.copyWith(city: 'Tashkent'));
        final revalidate = api.queueListings();
        final searchAAgain = state.search();
        expect(state.listings.single.id, 'a');
        expect(state.loading, isFalse);

        revalidate.complete(
          ListingsResult([_listing('a')], const [], const [], total: 1),
        );
        await searchAAgain;
        expect(state.listings.single.id, 'a');
      },
    );

    test(
      'a background revalidation failure leaves the cached page on screen',
      () async {
        final api = _QueueApi();
        final state = AppState(api)..filters = Filters(countries: {'UZ'});

        final first = api.queueListings();
        final searchA = state.search();
        first.complete(
          ListingsResult([_listing('a')], const [], const [], total: 1),
        );
        await searchA;

        state.updateFilters(state.filters.copyWith(query: 'two rooms'));
        final second = api.queueListings();
        final searchB = state.search();
        second.complete(
          ListingsResult([_listing('b')], const [], const [], total: 1),
        );
        await searchB;

        state.updateFilters(state.filters.copyWith(query: ''));
        final revalidate = api.queueListings();
        final searchAAgain = state.search();
        expect(state.listings.single.id, 'a'); // painted from cache

        // The zero-delay Timer that issues the revalidation runs after this
        // point, not before it -- complete the error only once _executeSearch
        // has actually awaited the future, so Dart's unhandled-error zone
        // detector sees a listener already attached rather than flagging a
        // completer that errored before anyone was listening.
        await Future<void>.delayed(Duration.zero);
        revalidate.completeError(Exception('network down'));
        await searchAAgain;

        expect(state.listings.single.id, 'a');
        expect(state.error, isNull);
        expect(state.loading, isFalse);
      },
    );

    test('an uncached combination still shows the blocking overlay', () async {
      final api = _QueueApi();
      final state = AppState(api)..filters = Filters(countries: {'UZ'});

      final pending = api.queueListings();
      final searchFuture = state.search();
      expect(state.loading, isTrue);

      pending.complete(
        ListingsResult([_listing('a')], const [], const [], total: 1),
      );
      await searchFuture;
      expect(state.loading, isFalse);
    });

    test(
      "reloadAll's fresh result is what a subsequent search serves from cache",
      () async {
        final api = _QueueApi();
        final state = AppState(api)..filters = Filters(countries: {'UZ'});

        final first = api.queueListings();
        final searchA = state.search();
        first.complete(
          ListingsResult([_listing('stale')], const [], const [], total: 1),
        );
        await searchA;

        final forced = api.queueListings();
        final reload = state.reloadAll();
        forced.complete(
          ListingsResult([_listing('fresh')], const [], const [], total: 1),
        );
        await reload;
        expect(state.listings.single.id, 'fresh');

        // The identical combination should now serve the *reloaded* result,
        // not whatever the plain search cached before reloadAll ran.
        final callsBefore = api.listingsCalls;
        final searchAgain = state.search();
        expect(state.listings.single.id, 'fresh');
        await searchAgain;
        expect(api.listingsCalls, callsBefore + 1); // still revalidates
      },
    );
  });

  group('map cache', () {
    test(
      're-visiting a filter combination repaints pins from cache without the loading flag',
      () async {
        final api = _QueueApi();
        final state = AppState(api)
          ..filters = Filters(countries: {'UZ'}, city: 'Tashkent');

        final firstMap = api.queueMap();
        final mapA = state.loadMapListings();
        expect(state.mapLoading, isTrue);
        firstMap.complete([_point('a')]);
        await mapA;
        expect(state.mapListings.single.id, 'a');

        state.updateFilters(state.filters.copyWith(city: 'Samarkand'));
        final secondMap = api.queueMap();
        final mapB = state.loadMapListings();
        secondMap.complete([_point('b')]);
        await mapB;

        state.updateFilters(state.filters.copyWith(city: 'Tashkent'));
        final revalidateMap = api.queueMap();
        final mapAAgain = state.loadMapListings();
        // Painted from cache immediately; the blocking overlay never engages.
        expect(state.mapListings.single.id, 'a');
        expect(state.mapLoading, isFalse);

        revalidateMap.complete([_point('a')]);
        await mapAAgain;
        expect(state.mapListings.single.id, 'a');
      },
    );

    test(
      'a failed map revalidation leaves the cached pins in place',
      () async {
        final api = _QueueApi();
        final state = AppState(api)..filters = Filters(countries: {'UZ'});

        final firstMap = api.queueMap();
        final mapA = state.loadMapListings();
        firstMap.complete([_point('a')]);
        await mapA;

        state.updateFilters(state.filters.copyWith(query: 'two rooms'));
        final secondMap = api.queueMap();
        final mapB = state.loadMapListings();
        secondMap.complete([_point('b')]);
        await mapB;

        state.updateFilters(state.filters.copyWith(query: ''));
        final revalidateMap = api.queueMap();
        final mapAAgain = state.loadMapListings();
        expect(state.mapListings.single.id, 'a');

        await Future<void>.delayed(Duration.zero);
        revalidateMap.completeError(Exception('network down'));
        await mapAAgain;

        expect(state.mapListings.single.id, 'a');
        expect(state.mapLoading, isFalse);
      },
    );
  });
}

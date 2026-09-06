import 'dart:async';

import 'package:flat_finder/models/district_zone.dart';
import 'package:flat_finder/models/filters.dart';
import 'package:flat_finder/models/listing.dart';
import 'package:flat_finder/services/api_service.dart';
import 'package:flat_finder/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Listing _listing(String id) => Listing.fromJson({
      'id': id,
      'source': 'olx',
      'country': 'UZ',
      'title': 'listing $id',
      'propertyType': 'flat',
      'currency': 'USD',
      'city': 'Tashkent',
      'url': 'https://example.test/$id',
      'description': '',
      'tags': <String>[],
    });

class _QueueApi extends ApiService {
  _QueueApi() : super(baseUrl: 'http://test.invalid');

  final List<Completer<ListingsResult>> requests = [];
  int mapZonesCalls = 0;

  @override
  Future<ListingsResult> fetchListings(
    Filters filters, {
    bool force = false,
    String? cursor,
  }) {
    final request = Completer<ListingsResult>();
    requests.add(request);
    return request.future;
  }

  @override
  Future<MapZones> fetchMapZones(
    String country,
    String city, {
    String locale = '',
  }) {
    mapZonesCalls += 1;
    return Completer<MapZones>().future;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('metro search first paint no longer waits for district-zones', () async {
    final api = _QueueApi();
    final state = AppState(api)
      ..filters = Filters(
        countries: {'UZ'},
        city: 'Tashkent',
        metro: {'Novza', 'Chilonzor'},
        metroMaxM: 800,
        metroBearingFrom: 250,
        metroBearingTo: 290,
      );

    final search = state.search(immediate: true);
    await Future<void>.delayed(Duration.zero);
    expect(api.requests, hasLength(1));
    api.requests.single.complete(
      ListingsResult([_listing('server-filtered')], const [], const [], total: 1),
    );

    await search.timeout(const Duration(seconds: 1));
    expect(state.listings.single.id, 'server-filtered');
    expect(
      api.mapZonesCalls,
      0,
      reason: 'geo membership is backend-owned; zones are rendering metadata',
    );
  });

  test('different server sort does not reuse another sort cursor cache', () async {
    final api = _QueueApi();
    final state = AppState(api)
      ..filters = Filters(countries: {'UZ'}, sort: SortBy.relevance);

    final first = state.search(immediate: true);
    await Future<void>.delayed(Duration.zero);
    api.requests[0].complete(
      ListingsResult([_listing('relevance')], const [], const [], total: 1),
    );
    await first;

    state.filters = state.filters.copyWith(sort: SortBy.priceAsc);
    final sorted = state.search(immediate: true);

    // A stale relevance cache hit would keep loading=false and paint its old
    // page/cursor immediately. A sort-aware cache must perform a fresh root fetch.
    expect(state.loading, isTrue);
    expect(state.listings.single.id, 'relevance');
    await Future<void>.delayed(Duration.zero);
    expect(api.requests, hasLength(2));
    api.requests[1].complete(
      ListingsResult([_listing('price-asc')], const [], const [], total: 1),
    );
    await sorted;
    expect(state.listings.single.id, 'price-asc');
  });

  test('removing a listing invalidates feed cache so it cannot resurrect', () async {
    final api = _QueueApi();
    final state = AppState(api)..filters = Filters(countries: {'UZ'});

    final first = state.search(immediate: true);
    await Future<void>.delayed(Duration.zero);
    api.requests[0].complete(
      ListingsResult([_listing('gone')], const [], const [], total: 1),
    );
    await first;
    expect(state.listings.single.id, 'gone');

    state.removeListing('olx', 'UZ', 'gone');
    expect(state.listings, isEmpty);

    final refresh = state.search(immediate: true);
    expect(
      state.listings,
      isEmpty,
      reason: 'a deleted cached snapshot must not be painted again',
    );
    expect(state.loading, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(api.requests, hasLength(2));
    api.requests[1].complete(
      ListingsResult(const [], const [], const [], total: 0),
    );
    await refresh;
    expect(state.listings, isEmpty);
  });
}

import 'dart:async';

import 'package:flat_finder/models/district_zone.dart';
import 'package:flat_finder/models/filters.dart';
import 'package:flat_finder/models/listing.dart';
import 'package:flat_finder/models/map_listing_point.dart';
import 'package:flat_finder/services/api_service.dart';
import 'package:flat_finder/state/app_state.dart';
import 'package:flat_finder/utils/metro_proximity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _novzaLat = 41.2920278;
const _novzaLng = 69.2233417;

DistrictZone _station(String name, {double? lat, double? lng}) => DistrictZone(
      id: 'metro:$name',
      parentId: null,
      type: 'metro',
      name: name,
      label: name,
      lat: lat ?? _novzaLat,
      lng: lng ?? _novzaLng,
      radiusM: 200,
      colorHex: '#2563eb',
      boundaryRings: const [],
    );

LatLng _at(double bearing, double metres) =>
    destinationPoint(const LatLng(_novzaLat, _novzaLng), bearing, metres);

Listing _listingAt(String id, LatLng point) => Listing.fromJson({
      'id': id,
      'source': 'olx',
      'country': 'UZ',
      'title': 'listing $id',
      'propertyType': 'flat',
      'currency': 'USD',
      'city': 'Tashkent',
      'url': 'https://example.test/olx/UZ/$id',
      'description': '',
      'tags': <String>[],
      'lat': point.latitude,
      'lng': point.longitude,
    });

MapListingPoint _pointAt(String id, LatLng point) => MapListingPoint(
      id: id,
      source: 'olx',
      country: 'UZ',
      lat: point.latitude,
      lng: point.longitude,
      title: 'listing $id',
      currency: 'USD',
      city: 'Tashkent',
      propertyType: 'flat',
    );

class _FakeApi extends ApiService {
  _FakeApi({required this.listings, required this.points, required this.zones})
      : super(baseUrl: 'http://test.invalid');

  final List<Listing> listings;
  final List<MapListingPoint> points;
  final MapZones zones;
  final List<Map<String, String>> listingsCalls = [];
  final List<Map<String, String>> mapCalls = [];

  @override
  Future<ListingsResult> fetchListings(
    Filters filters, {
    bool force = false,
    String? cursor,
  }) async {
    // The production ApiService facade sends the complete serializer upstream;
    // emulate that wire contract rather than the removed legacy strip logic.
    listingsCalls.add(filters.toQueryParams());
    return ListingsResult(listings, const [], const [], total: listings.length);
  }

  @override
  Future<List<MapListingPoint>> fetchMapListings(Filters filters) async {
    mapCalls.add(filters.toQueryParams());
    return points;
  }

  @override
  Future<MapZones> fetchMapZones(
    String country,
    String city, {
    String locale = '',
  }) async =>
      zones;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('single-station radius and arc are sent upstream and not re-filtered',
      () async {
    final listings = [
      _listingAt('west-inside', _at(270, 600)),
      // Deliberately contradictory to the requested arc: if Flutter changes
      // membership again, this row disappears and the test catches it.
      _listingAt('east-but-returned-by-server', _at(90, 400)),
    ];
    final points = [
      _pointAt('west-inside', _at(270, 600)),
      _pointAt('east-but-returned-by-server', _at(90, 400)),
    ];
    final api = _FakeApi(
      listings: listings,
      points: points,
      zones: MapZones(metroStations: [_station('Novza')]),
    );
    final state = AppState(api)
      ..filters = Filters(
        countries: {'UZ'},
        city: 'Tashkent',
        metro: {'Novza'},
        metroMaxM: 780,
        metroBearingFrom: 252,
        metroBearingTo: 288,
      );

    await state.search();
    expect(state.listings.map((l) => l.id).toList(),
        ['west-inside', 'east-but-returned-by-server']);
    expect(api.listingsCalls.single['metro'], 'Novza');
    expect(api.listingsCalls.single['metroMaxM'], '780');
    expect(api.listingsCalls.single['metroArc'], '252,288');

    await state.loadMapListings();
    expect(state.mapListings.map((p) => p.id).toList(),
        ['west-inside', 'east-but-returned-by-server']);
    expect(api.mapCalls.single['metro'], 'Novza');
    expect(api.mapCalls.single['metroArc'], '252,288');
  });

  test('several stations and radius are sent as a backend union', () async {
    const other = 'Chilonzor';
    final listings = [
      _listingAt('by-novza', _at(270, 300)),
      _listingAt('by-other', const LatLng(41.312, 69.243)),
      _listingAt('server-authoritative-third', const LatLng(41.35, 69.35)),
    ];
    final api = _FakeApi(
      listings: listings,
      points: const [],
      zones: MapZones(
        metroStations: [
          _station('Novza'),
          _station(other, lat: 41.312, lng: 69.243),
        ],
      ),
    );
    final state = AppState(api)
      ..filters = Filters(
        countries: {'UZ'},
        city: 'Tashkent',
        metro: {'Novza', other},
        metroMaxM: 800,
      );

    await state.search();

    final sent = api.listingsCalls.single;
    expect(sent['metro']!.split(',').toSet(), {'Novza', other});
    expect(sent['metroMaxM'], '800');
    expect(state.listings.map((l) => l.id).toList(),
        ['by-novza', 'by-other', 'server-authoritative-third']);
  });

  test('missing listing coordinates are a backend concern, not a client drop',
      () async {
    final noCoords = Listing.fromJson({
      'id': 'no-coords',
      'source': 'olx',
      'country': 'UZ',
      'title': 'no coords',
      'propertyType': 'flat',
      'currency': 'USD',
      'city': 'Tashkent',
      'url': 'https://example.test/olx/UZ/no-coords',
      'description': '',
      'tags': <String>[],
    });
    final api = _FakeApi(
      listings: [noCoords],
      points: const [],
      zones: MapZones(metroStations: [_station('Novza')]),
    );
    final state = AppState(api)
      ..filters = Filters(
        countries: {'UZ'},
        city: 'Tashkent',
        metro: {'Novza'},
        metroMaxM: 780,
      );

    await state.search();
    expect(state.listings.single.id, 'no-coords');
  });
}

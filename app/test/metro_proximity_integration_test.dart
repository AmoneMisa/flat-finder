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

// Novza, Tashkent -- the same worked example as tests/flat-metro-proximity
// on the web client and metro_proximity_test.dart here: "near Novza, west
// side, within 780m".
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
    listingsCalls.add(filters.toUpstreamQueryParams());
    return ListingsResult(listings, const [], const [], total: listings.length);
  }

  @override
  Future<List<MapListingPoint>> fetchMapListings(Filters filters) async {
    mapCalls.add(filters.toUpstreamQueryParams());
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

  test(
      'a west wedge around one station narrows both the list and the map, and the server still gets metro+metroMaxM',
      () async {
    // The fake server response already excludes west-too-far (900m > the
    // 780m metroMaxM it was sent): a real server does its own distance
    // narrowing for a single station, which is exactly why AppState does
    // NOT re-check distance client-side in this case (see
    // _metroProximityFor) -- only the arc, which the server never receives
    // at all, is enforced here. east-inside-radius is within distance but
    // the wrong direction, so only the arc removes it.
    final listings = [
      _listingAt('west-inside', _at(270, 600)),
      _listingAt('east-inside-radius', _at(90, 400)),
    ];
    final points = [
      _pointAt('west-inside', _at(270, 600)),
      _pointAt('east-inside-radius', _at(90, 400)),
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
    expect(state.listings.map((l) => l.id).toList(), ['west-inside']);
    // Distance narrowing is still delegated to the server for one station.
    expect(api.listingsCalls.single['metro'], 'Novza');
    expect(api.listingsCalls.single['metroMaxM'], '780');
    // The arc has no server representation and must never be sent.
    expect(api.listingsCalls.single.containsKey('metroArc'), isFalse);

    await state.loadMapListings();
    expect(state.mapListings.map((p) => p.id).toList(), ['west-inside']);
  });

  test(
      'a single station trusts the server for distance and only re-checks the arc',
      () async {
    // A listing the server would never have returned for metroMaxM: 780 (it
    // is 900m out), included here anyway to prove AppState does not
    // re-filter it -- only a real server enforces that distance for one
    // station. If this regresses to double-checking distance too, this
    // listing would vanish and the test would need updating, which is the
    // point: it documents the trust boundary explicitly.
    final listings = [_listingAt('too-far-but-trusted', _at(270, 900))];
    final api = _FakeApi(
      listings: listings,
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
    expect(state.listings.single.id, 'too-far-but-trusted');
  });

  test(
      'several stations send nothing metro-related upstream and are unioned client-side',
      () async {
    const other = 'Chilonzor';
    final listings = [
      _listingAt('by-novza', _at(270, 300)),
      _listingAt(
        'by-other',
        LatLng(_novzaLat + 0.02, _novzaLng + 0.02 + 0.0001),
      ),
      _listingAt('by-neither', const LatLng(41.35, 69.35)),
    ];
    final otherLat = _novzaLat + 0.02;
    final otherLng = _novzaLng + 0.02;
    final api = _FakeApi(
      listings: listings,
      points: const [],
      zones: MapZones(
        metroStations: [
          _station('Novza'),
          _station(other, lat: otherLat, lng: otherLng),
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

    expect(api.listingsCalls.single.containsKey('metro'), isFalse);
    expect(api.listingsCalls.single.containsKey('metroMaxM'), isFalse);
    expect(
      state.listings.map((l) => l.id).toSet(),
      {'by-novza', 'by-other'},
    );
  });

  test(
      'a listing with no coordinates survives the filter rather than vanishing',
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

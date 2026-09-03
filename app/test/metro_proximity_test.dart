import 'package:flat_finder/utils/metro_proximity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

// Novza, Tashkent -- the worked example: "near Novza, west side, within 780m".
// Same coordinates and expectations as tests/flat-metro-proximity.test.mjs on
// the web client, so the two geometries can be trusted to agree.
const _novza = MetroPoint(name: 'Novza', lat: 41.2920278, lng: 69.2233417);

LatLng _at(double bearing, double metres) =>
    destinationPoint(LatLng(_novza.lat, _novza.lng), bearing, metres);

void main() {
  test('distance and bearing round-trip through destinationPoint', () {
    for (final bearing in [0.0, 45.0, 137.0, 252.0, 270.0, 288.0, 359.0]) {
      final target = _at(bearing, 780);
      final origin = LatLng(_novza.lat, _novza.lng);
      expect((metresBetween(origin, target) - 780).abs(), lessThan(0.5));
      final measured = bearingBetween(origin, target);
      final diff = ((measured - bearing) % 360 + 360) % 360;
      expect(diff < 0.01 || diff > 359.99, isTrue,
          reason: 'bearing at $bearing');
    }
  });

  test('an arc is the clockwise sweep, so it may straddle north', () {
    expect(bearingWithinArc(0, 340, 20), isTrue);
    expect(bearingWithinArc(350, 340, 20), isTrue);
    expect(bearingWithinArc(19, 340, 20), isTrue);
    expect(bearingWithinArc(180, 340, 20), isFalse);
    // Handles that have not been separated yet must not reject everything.
    expect(bearingWithinArc(123, 90, 90), isTrue);
  });

  test('a west wedge keeps west listings and drops the rest', () {
    final points = {
      'west-inside': _at(270, 600),
      'west-edge': _at(255, 770),
      'west-too-far': _at(270, 900),
      'east-inside-radius': _at(90, 400),
      'north-inside-radius': _at(0, 300),
    };
    final proximity = const MetroProximity(
      stations: [_novza],
      maxM: 780,
      bearingFrom: 252,
      bearingTo: 288,
    );
    final kept = applyMetroProximity(
      points.entries.toList(),
      proximity,
      (entry) => entry.value,
    ).map((e) => e.key).toList();
    expect(kept, ['west-inside', 'west-edge']);
  });

  test('several stations are a union, not an intersection', () {
    const other = MetroPoint(name: 'Other', lat: 41.31, lng: 69.28);
    final points = {
      'by-novza': _at(270, 300),
      'by-other': const LatLng(41.311, 69.28),
      'by-neither': const LatLng(41.35, 69.35),
    };
    final proximity =
        const MetroProximity(stations: [_novza, other], maxM: 800);
    final kept = applyMetroProximity(
      points.entries.toList(),
      proximity,
      (entry) => entry.value,
    ).map((e) => e.key).toList()
      ..sort();
    expect(kept, ['by-novza', 'by-other']);
  });

  test('items without usable coordinates are kept, not silently dropped', () {
    final points = <String, LatLng?>{
      'no-coords': null,
      'far-east': _at(90, 5000),
    };
    final proximity = const MetroProximity(stations: [_novza], maxM: 780);
    final kept = applyMetroProximity(
      points.entries.toList(),
      proximity,
      (entry) => entry.value,
    ).map((e) => e.key).toList();
    expect(kept, ['no-coords']);
  });

  test('an inert filter passes every item through untouched', () {
    final items = ['a'];
    expect(const MetroProximity().isEmpty, isTrue);
    expect(const MetroProximity(stations: [_novza]).isEmpty, isTrue);
    expect(
        const MetroProximity(stations: [_novza], maxM: 500).isEmpty, isFalse);
    expect(
      applyMetroProximity(items, const MetroProximity(), (_) => _at(90, 9000)),
      same(items),
    );
  });

  test('the drawn wedge closes through the station, a full circle does not',
      () {
    final origin = LatLng(_novza.lat, _novza.lng);
    final wedge = sectorPolygon(origin, 780, from: 252, to: 288);
    expect(wedge.first.latitude, _novza.lat);
    expect(wedge.first.longitude, _novza.lng);
    for (final point in wedge.skip(1)) {
      expect((metresBetween(origin, point) - 780).abs(), lessThan(0.5));
    }
    final circle = sectorPolygon(origin, 780);
    expect(metresBetween(origin, circle.first), greaterThan(700));
  });

  test('compass points and their arcs agree with each other', () {
    expect(compassPointFor(247.5, 292.5), 'W');
    expect(compassPointFor(252, 288), 'W');
    expect(compassPointFor(340, 20), 'N');
    expect(arcForCompassPoint('W'), (247.5, 292.5));
    expect(arcForCompassPoint('N'), (337.5, 22.5));
  });
}

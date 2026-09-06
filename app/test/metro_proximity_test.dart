import 'package:flat_finder/utils/metro_proximity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

// Novza, Tashkent -- geometry here is presentation geometry only. Membership
// itself is decided by the backend/database before count and pagination.
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
    expect(bearingWithinArc(123, 90, 90), isTrue);
  });

  test('legacy post-filter shim never changes backend membership', () {
    final points = {
      'west-inside': _at(270, 600),
      'west-too-far': _at(270, 900),
      'east-inside-radius': _at(90, 400),
      'no-coords': null,
    };
    final items = points.entries.toList();
    final proximity = const MetroProximity(
      stations: [_novza],
      maxM: 780,
      bearingFrom: 252,
      bearingTo: 288,
    );
    final kept = applyMetroProximity(items, proximity, (entry) => entry.value);
    expect(kept, same(items));
  });

  test('an inert overlay is recognized without affecting results', () {
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

  group('what a map tap near a station means', () {
    test('a tap on the dot picks the station at the default radius', () {
      expect(
        metroTapRadiusM(
          screenDistancePx: 5,
          metresFromStation: 40,
          hasSelection: false,
        ),
        defaultMetroRadiusM,
      );
      expect(
        metroTapRadiusM(
          screenDistancePx: 5,
          metresFromStation: 40,
          hasSelection: true,
        ),
        defaultMetroRadiusM,
      );
    });

    test('with rings drawn, a tap inside one adopts that band', () {
      double? tap(double metres) => metroTapRadiusM(
            screenDistancePx: 200,
            metresFromStation: metres,
            hasSelection: false,
          );
      expect(tap(150), 200);
      expect(tap(400), 500);
      expect(tap(900), 1000);
      expect(tap(1400), isNull);
    });

    test('with a selection active, only the dot counts -- not the old 1km grab',
        () {
      expect(
        metroTapRadiusM(
          screenDistancePx: 200,
          metresFromStation: 400,
          hasSelection: true,
        ),
        isNull,
      );
    });

    test('the slop is a pixel budget, so zoom does not change the target', () {
      for (final metres in [30.0, 300.0, 3000.0]) {
        expect(
          metroTapRadiusM(
            screenDistancePx: 10,
            metresFromStation: metres,
            hasSelection: true,
          ),
          defaultMetroRadiusM,
          reason: 'at $metres m',
        );
      }
    });
  });
}

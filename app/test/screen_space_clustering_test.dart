import 'dart:math' as math;

import 'package:flat_finder/utils/screen_space_clustering.dart';
import 'package:flutter_test/flutter_test.dart';

class _Item {
  const _Item(this.id, this.x, this.y, this.lat, this.lng);

  final int id;
  final double x;
  final double y;
  final double lat;
  final double lng;
}

List<List<int>> _naiveClusters(
  List<_Item> items, {
  required double radius,
  required double worldWidth,
}) {
  final seeds = <ScreenCoordinate>[];
  final groups = <List<int>>[];
  final radiusSquared = radius * radius;

  for (final item in items) {
    int? target;
    for (var i = 0; i < groups.length; i++) {
      final seed = seeds[i];
      final dx = wrappedScreenDx(seed.x, item.x, worldWidth);
      final dy = seed.y - item.y;
      if (dx * dx + dy * dy <= radiusSquared) {
        target = i;
        break;
      }
    }
    if (target == null) {
      seeds.add(ScreenCoordinate(item.x, item.y));
      groups.add([item.id]);
    } else {
      groups[target].add(item.id);
    }
  }
  return groups;
}

Set<int> _naiveCollisionFree({
  required List<ScreenCoordinate> points,
  required List<bool> singleton,
  required double priceRadius,
  required double clusterRadius,
  required double padding,
  required double worldWidth,
}) {
  final result = <int>{};
  for (var i = 0; i < points.length; i++) {
    if (!singleton[i]) continue;
    var clear = true;
    for (var j = 0; j < points.length; j++) {
      if (i == j) continue;
      final dx = wrappedScreenDx(points[i].x, points[j].x, worldWidth);
      final dy = points[i].y - points[j].y;
      final otherRadius = singleton[j] ? priceRadius : clusterRadius;
      final threshold = priceRadius + otherRadius + padding;
      if (dx * dx + dy * dy < threshold * threshold) {
        clear = false;
        break;
      }
    }
    if (clear) result.add(i);
  }
  return result;
}

void main() {
  test('spatial hash preserves greedy first-match clustering', () {
    const worldWidth = 4096.0;
    const radius = 38.0;
    final random = math.Random(20260831);

    for (var round = 0; round < 30; round++) {
      final items = <_Item>[
        // Explicit wrap-around neighbours exercise the antimeridian path.
        const _Item(-2, 2, 200, 1, 1),
        const _Item(-1, worldWidth - 3, 202, 2, 2),
        for (var i = 0; i < 500; i++)
          _Item(
            i,
            random.nextDouble() * worldWidth,
            random.nextDouble() * 3000,
            random.nextDouble() * 180 - 90,
            random.nextDouble() * 360 - 180,
          ),
      ];

      final expected = _naiveClusters(
        items,
        radius: radius,
        worldWidth: worldWidth,
      );
      final actual = greedyScreenSpaceClusters<_Item>(
        items,
        project: (item) => ScreenCoordinate(item.x, item.y),
        latitudeOf: (item) => item.lat,
        longitudeOf: (item) => item.lng,
        radiusPx: radius,
        worldWidth: worldWidth,
      ).map((cluster) => cluster.items.map((item) => item.id).toList()).toList();

      expect(actual, expected, reason: 'round $round');
    }
  });

  test('spatial collision lookup matches all-pairs price-marker rule', () {
    const worldWidth = 8192.0;
    const priceRadius = 40.5;
    const clusterRadius = 16.0;
    const padding = 6.0;
    final random = math.Random(42);

    for (var round = 0; round < 30; round++) {
      final points = <ScreenCoordinate>[
        const ScreenCoordinate(2, 100),
        const ScreenCoordinate(worldWidth - 2, 100),
        for (var i = 0; i < 600; i++)
          ScreenCoordinate(
            random.nextDouble() * worldWidth,
            random.nextDouble() * 4000,
          ),
      ];
      final singleton = [
        true,
        true,
        for (var i = 0; i < 600; i++) random.nextBool(),
      ];

      final expected = _naiveCollisionFree(
        points: points,
        singleton: singleton,
        priceRadius: priceRadius,
        clusterRadius: clusterRadius,
        padding: padding,
        worldWidth: worldWidth,
      );
      final actual = collisionFreePriceMarkerIndexes(
        points: points,
        singleton: singleton,
        priceMarkerRadius: priceRadius,
        clusterMarkerRadius: clusterRadius,
        padding: padding,
        worldWidth: worldWidth,
      );

      expect(actual, expected, reason: 'round $round');
    }
  });
}

/// Pure screen-space helpers for map marker clustering and collision checks.
///
/// The algorithms use a fixed-size spatial hash so each point only inspects
/// nearby buckets instead of scanning every cluster/marker already produced.
/// Exact distance checks still decide membership, and greedy clustering keeps
/// the earliest matching cluster to preserve the existing map semantics.
class ScreenCoordinate {
  const ScreenCoordinate(this.x, this.y);

  final double x;
  final double y;
}

class ScreenSpaceCluster<T> {
  ScreenSpaceCluster({
    required this.seedX,
    required this.seedY,
    required this.latitudeSum,
    required this.longitudeSum,
    required this.items,
  });

  final double seedX;
  final double seedY;
  double latitudeSum;
  double longitudeSum;
  final List<T> items;
}

typedef ScreenProjector<T> = ScreenCoordinate Function(T item);
typedef CoordinateValue<T> = double Function(T item);

double wrappedScreenDx(double a, double b, double worldWidth) {
  final raw = (a - b).abs();
  if (worldWidth <= 0 || !worldWidth.isFinite) return raw;
  final normalized = raw % worldWidth;
  final wrapped = worldWidth - normalized;
  return normalized < wrapped ? normalized : wrapped;
}

(int, int) _cellFor(double x, double y, double cellSize) =>
    ((x / cellSize).floor(), (y / cellSize).floor());

List<int> _candidateIndexes(
  Map<(int, int), List<int>> grid,
  ScreenCoordinate point, {
  required double cellSize,
  required double worldWidth,
}) {
  final candidates = <int>{};
  final xVariants = worldWidth > 0 && worldWidth.isFinite
      ? <double>[point.x, point.x - worldWidth, point.x + worldWidth]
      : <double>[point.x];

  for (final x in xVariants) {
    final (cellX, cellY) = _cellFor(x, point.y, cellSize);
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        final bucket = grid[(cellX + dx, cellY + dy)];
        if (bucket != null) candidates.addAll(bucket);
      }
    }
  }

  final sorted = candidates.toList()..sort();
  return sorted;
}

/// Greedy clustering equivalent to scanning all previously created clusters,
/// but with nearby bucket lookup. When more than one existing cluster is in
/// range, the lowest cluster index wins, matching the old first-match scan.
List<ScreenSpaceCluster<T>> greedyScreenSpaceClusters<T>(
  List<T> items, {
  required ScreenProjector<T> project,
  required CoordinateValue<T> latitudeOf,
  required CoordinateValue<T> longitudeOf,
  required double radiusPx,
  required double worldWidth,
}) {
  if (items.isEmpty) return const [];
  if (radiusPx <= 0 || !radiusPx.isFinite) {
    throw ArgumentError.value(radiusPx, 'radiusPx', 'must be finite and > 0');
  }

  final clusters = <ScreenSpaceCluster<T>>[];
  final grid = <(int, int), List<int>>{};
  final radiusSquared = radiusPx * radiusPx;

  for (final item in items) {
    final point = project(item);
    int? targetIndex;

    for (final index in _candidateIndexes(
      grid,
      point,
      cellSize: radiusPx,
      worldWidth: worldWidth,
    )) {
      final cluster = clusters[index];
      final dx = wrappedScreenDx(cluster.seedX, point.x, worldWidth);
      final dy = cluster.seedY - point.y;
      if (dx * dx + dy * dy <= radiusSquared) {
        targetIndex = index;
        break;
      }
    }

    if (targetIndex == null) {
      final index = clusters.length;
      clusters.add(
        ScreenSpaceCluster<T>(
          seedX: point.x,
          seedY: point.y,
          latitudeSum: latitudeOf(item),
          longitudeSum: longitudeOf(item),
          items: [item],
        ),
      );
      final cell = _cellFor(point.x, point.y, radiusPx);
      (grid[cell] ??= <int>[]).add(index);
    } else {
      final cluster = clusters[targetIndex];
      cluster.items.add(item);
      cluster.latitudeSum += latitudeOf(item);
      cluster.longitudeSum += longitudeOf(item);
    }
  }

  return clusters;
}

/// Returns singleton marker indexes whose prospective price pill cannot
/// overlap any neighbouring singleton price pill or cluster marker.
///
/// [singleton] describes the group shape, not whether the neighbouring marker
/// ultimately receives a price pill. This intentionally mirrors the previous
/// conservative collision rule.
Set<int> collisionFreePriceMarkerIndexes({
  required List<ScreenCoordinate> points,
  required List<bool> singleton,
  required double priceMarkerRadius,
  required double clusterMarkerRadius,
  required double padding,
  required double worldWidth,
}) {
  if (points.length != singleton.length) {
    throw ArgumentError('points and singleton must have the same length');
  }
  if (points.isEmpty) return const {};

  final maxCollisionDistance = priceMarkerRadius * 2 + padding;
  if (maxCollisionDistance <= 0 || !maxCollisionDistance.isFinite) {
    throw ArgumentError.value(
      maxCollisionDistance,
      'maxCollisionDistance',
      'must be finite and > 0',
    );
  }

  final grid = <(int, int), List<int>>{};
  for (var i = 0; i < points.length; i++) {
    final point = points[i];
    final cell = _cellFor(point.x, point.y, maxCollisionDistance);
    (grid[cell] ??= <int>[]).add(i);
  }

  final clear = <int>{};
  for (var i = 0; i < points.length; i++) {
    if (!singleton[i]) continue;
    final point = points[i];
    var collides = false;
    for (final otherIndex in _candidateIndexes(
      grid,
      point,
      cellSize: maxCollisionDistance,
      worldWidth: worldWidth,
    )) {
      if (otherIndex == i) continue;
      final otherPoint = points[otherIndex];
      final dx = wrappedScreenDx(point.x, otherPoint.x, worldWidth);
      final dy = point.y - otherPoint.y;
      final otherRadius = singleton[otherIndex]
          ? priceMarkerRadius
          : clusterMarkerRadius;
      final threshold = priceMarkerRadius + otherRadius + padding;
      if (dx * dx + dy * dy < threshold * threshold) {
        collides = true;
        break;
      }
    }
    if (!collides) clear.add(i);
  }

  return clear;
}

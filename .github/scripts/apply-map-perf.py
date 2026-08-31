from pathlib import Path

path = Path('app/lib/widgets/map_view.dart')
text = path.read_text(encoding='utf-8')
original = text

old_import = "import '../utils/price_tone.dart';\n"
new_import = "import '../utils/price_tone.dart';\nimport '../utils/screen_space_clustering.dart';\n"
if "screen_space_clustering.dart" not in text:
    if old_import not in text:
        raise SystemExit('price_tone import anchor not found')
    text = text.replace(old_import, new_import, 1)

old_cluster_block = r'''  Offset _worldPixel(LatLng point, [double? zoom]) {
    final z = zoom ?? _zoom;
    final worldSize = 256.0 * math.pow(2, z).toDouble();
    final lat = point.latitude.clamp(-85.05112878, 85.05112878).toDouble();
    final sinLat = math.sin(lat * math.pi / 180);
    final x = (point.longitude + 180) / 360 * worldSize;
    final y = (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) *
        worldSize;
    return Offset(x, y);
  }

  double _wrappedDx(double a, double b, [double? zoom]) {
    final z = zoom ?? _zoom;
    final worldSize = 256.0 * math.pow(2, z).toDouble();
    final raw = (a - b).abs();
    return math.min(raw, worldSize - raw);
  }

  /// Greedy screen-space clustering, equivalent to FlatMap.client.vue's
  /// latLngToContainerPoint + 38px distance check.
  List<_PinGroup> _groupsFor(List<Listing> located, {double? zoom}) {
    if (located.isEmpty) return const [];
    final clusters = <_ClusterAccumulator>[];
    for (final listing in located) {
      final point = _worldPixel(LatLng(listing.lat!, listing.lng!), zoom);
      _ClusterAccumulator? target;
      for (final cluster in clusters) {
        final dx = _wrappedDx(cluster.x, point.dx, zoom);
        final dy = cluster.y - point.dy;
        if (dx * dx + dy * dy <= _clusterRadiusPx * _clusterRadiusPx) {
          target = cluster;
          break;
        }
      }
      if (target == null) {
        clusters.add(
          _ClusterAccumulator(
            x: point.dx,
            y: point.dy,
            latSum: listing.lat!,
            lngSum: listing.lng!,
            listings: [listing],
          ),
        );
      } else {
        target.listings.add(listing);
        target.latSum += listing.lat!;
        target.lngSum += listing.lng!;
      }
    }

    return [
      for (final cluster in clusters)
        () {
          final keys = cluster.listings.map(_listingKey).toList()..sort();
          return _PinGroup(
            keys.join('|'),
            cluster.listings,
            LatLng(
              cluster.latSum / cluster.listings.length,
              cluster.lngSum / cluster.listings.length,
            ),
          );
        }(),
    ];
  }

  String? _expandedGroupKey;

  /// A price pill is wider than a point. Show it only when its complete
  /// screen rectangle cannot intersect any neighbouring standalone pill or
  /// cluster marker. Otherwise render the normal 16px point.
  bool _canShowStandalonePrice(_PinGroup group, List<_PinGroup> groups) {
    if (group.listings.length != 1) return false;
    final point = _worldPixel(group.point);
    for (final other in groups) {
      if (identical(other, group)) continue;
      final otherPoint = _worldPixel(other.point);
      final dx = _wrappedDx(point.dx, otherPoint.dx);
      final dy = (point.dy - otherPoint.dy).abs();
      final ownRadius = math.sqrt(
        math.pow(_priceMarkerWidth / 2, 2) +
            math.pow(_priceMarkerHeight / 2, 2),
      );
      final otherRadius = other.listings.length == 1 ? ownRadius : 16.0;
      final distance = math.sqrt(dx * dx + dy * dy);
      if (distance < ownRadius + otherRadius + 6) return false;
    }
    return true;
  }
'''

new_cluster_block = r'''  double _worldWidth([double? zoom]) {
    final z = zoom ?? _zoom;
    return 256.0 * math.pow(2, z).toDouble();
  }

  Offset _worldPixel(LatLng point, [double? zoom]) {
    final worldSize = _worldWidth(zoom);
    final lat = point.latitude.clamp(-85.05112878, 85.05112878).toDouble();
    final sinLat = math.sin(lat * math.pi / 180);
    final x = (point.longitude + 180) / 360 * worldSize;
    final y = (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) *
        worldSize;
    return Offset(x, y);
  }

  /// Greedy screen-space clustering equivalent to the previous all-cluster
  /// scan, but backed by a spatial hash. Exact 38px distance checks and the
  /// earliest matching cluster preserve the existing visual semantics.
  List<_PinGroup> _groupsFor(List<Listing> located, {double? zoom}) {
    if (located.isEmpty) return const [];
    final clusters = greedyScreenSpaceClusters<Listing>(
      located,
      project: (listing) {
        final point = _worldPixel(LatLng(listing.lat!, listing.lng!), zoom);
        return ScreenCoordinate(point.dx, point.dy);
      },
      latitudeOf: (listing) => listing.lat!,
      longitudeOf: (listing) => listing.lng!,
      radiusPx: _clusterRadiusPx,
      worldWidth: _worldWidth(zoom),
    );

    return [
      for (final cluster in clusters)
        () {
          final keys = cluster.items.map(_listingKey).toList()..sort();
          return _PinGroup(
            keys.join('|'),
            cluster.items,
            LatLng(
              cluster.latitudeSum / cluster.items.length,
              cluster.longitudeSum / cluster.items.length,
            ),
          );
        }(),
    ];
  }

  String? _expandedGroupKey;

  /// Price pills use the same conservative collision rule as before, but the
  /// complete set is computed once per map build through nearby spatial cells
  /// rather than scanning every group for every singleton marker.
  Set<String> _standalonePriceGroupKeys(List<_PinGroup> groups) {
    if (groups.isEmpty) return const {};
    final ownRadius = math.sqrt(
      math.pow(_priceMarkerWidth / 2, 2) +
          math.pow(_priceMarkerHeight / 2, 2),
    );
    final indexes = collisionFreePriceMarkerIndexes(
      points: [
        for (final group in groups)
          () {
            final point = _worldPixel(group.point);
            return ScreenCoordinate(point.dx, point.dy);
          }(),
      ],
      singleton: [for (final group in groups) group.listings.length == 1],
      priceMarkerRadius: ownRadius,
      clusterMarkerRadius: 16,
      padding: 6,
      worldWidth: _worldWidth(),
    );
    return {for (final index in indexes) groups[index].key};
  }
'''

if old_cluster_block in text:
    text = text.replace(old_cluster_block, new_cluster_block, 1)
elif '_standalonePriceGroupKeys' not in text:
    raise SystemExit('clustering block anchor not found')

old_marker_signature = "  List<Marker> _markersForGroup(_PinGroup group, List<_PinGroup> groups) {\n    if (group.listings.length == 1 && _canShowStandalonePrice(group, groups)) {"
new_marker_signature = "  List<Marker> _markersForGroup(_PinGroup group, bool showStandalonePrice) {\n    if (group.listings.length == 1 && showStandalonePrice) {"
if old_marker_signature in text:
    text = text.replace(old_marker_signature, new_marker_signature, 1)
elif 'bool showStandalonePrice' not in text:
    raise SystemExit('marker signature anchor not found')

old_build = "    final visible = _visible;\n    final groups = _groupsFor(visible);\n    final expandedGroup = _expandedGroup(groups);"
new_build = "    final visible = _visible;\n    final groups = _groupsFor(visible);\n    final standalonePriceGroupKeys = _standalonePriceGroupKeys(groups);\n    final expandedGroup = _expandedGroup(groups);"
if old_build in text:
    text = text.replace(old_build, new_build, 1)
elif 'standalonePriceGroupKeys' not in text:
    raise SystemExit('build anchor not found')

old_marker_call = "                    ..._markersForGroup(group, groups),"
new_marker_call = "                    ..._markersForGroup(\n                      group,\n                      standalonePriceGroupKeys.contains(group.key),\n                    ),"
if old_marker_call in text:
    text = text.replace(old_marker_call, new_marker_call, 1)
elif 'standalonePriceGroupKeys.contains(group.key)' not in text:
    raise SystemExit('marker call anchor not found')

old_accumulator = r'''class _ClusterAccumulator {
  _ClusterAccumulator({
    required this.x,
    required this.y,
    required this.latSum,
    required this.lngSum,
    required this.listings,
  });

  final double x;
  final double y;
  double latSum;
  double lngSum;
  final List<Listing> listings;
}

'''
if old_accumulator in text:
    text = text.replace(old_accumulator, '', 1)

if text == original:
    print('map perf patch already applied')
else:
    path.write_text(text, encoding='utf-8')
    print('map perf patch applied')

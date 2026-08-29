from pathlib import Path


def read(path: str) -> str:
    return Path(path).read_text()


def write(path: str, text: str) -> None:
    Path(path).write_text(text)


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly 1 match, got {count}")
    return text.replace(old, new, 1)


def replace_between(text: str, start: str, end: str, replacement: str, label: str) -> str:
    i = text.find(start)
    if i < 0:
        raise SystemExit(f"{label}: start marker not found")
    j = text.find(end, i + len(start))
    if j < 0:
        raise SystemExit(f"{label}: end marker not found")
    return text[:i] + replacement + text[j:]


def replace_tail(text: str, start: str, replacement: str, label: str) -> str:
    i = text.find(start)
    if i < 0:
        raise SystemExit(f"{label}: start marker not found")
    return text[:i] + replacement


# Searchable dropdowns: make an actual placeholder visible inside an empty
# field instead of only having the floating label on the border.
path = "app/lib/widgets/searchable_dropdown.dart"
text = read(path)
text = replace_once(
    text,
    """    this.onTextChanged,\n    this.labelOf,\n  });""",
    """    this.onTextChanged,\n    this.labelOf,\n    this.placeholder,\n  });""",
    "searchable constructor",
)
text = replace_once(
    text,
    """  final ValueChanged<String>? onTextChanged;\n  final String Function(String)? labelOf;""",
    """  final ValueChanged<String>? onTextChanged;\n  final String Function(String)? labelOf;\n  final String? placeholder;""",
    "searchable fields",
)
text = replace_once(
    text,
    """          labelText: hint,\n          border: const OutlineInputBorder(),""",
    """          labelText: hint,\n          hintText: placeholder ?? hint,\n          border: const OutlineInputBorder(),""",
    "searchable placeholder",
)
text = replace_once(
    text,
    """              child: ListView(\n                padding: EdgeInsets.zero,""",
    """              child: ListView(\n                padding: const EdgeInsets.symmetric(vertical: 4),""",
    "searchable dropdown list top inset",
)
write(path, text)


# Full filter sheet placeholders. Keep labels semantic and use hintText for
# examples/default direction, matching the compact filter row.
path = "app/lib/widgets/filter_sheet.dart"
text = read(path)
text = replace_once(
    text,
    """                    decoration: InputDecoration(\n                      labelText: s.t('keywordHint'),\n                      border: const OutlineInputBorder(),\n                      prefixIcon: const Icon(Icons.search),\n                    ),""",
    """                    decoration: InputDecoration(\n                      labelText: s.t('keyword'),\n                      hintText: s.t('keywordHint'),\n                      border: const OutlineInputBorder(),\n                      prefixIcon: const Icon(Icons.search),\n                    ),""",
    "filter keyword placeholder",
)
text = replace_once(
    text,
    """                              hint: s.t('anyMicrodistrict'),\n                              options: _cityLoc!.microdistricts,""",
    """                              hint: s.t('anyMicrodistrict'),\n                              placeholder: s.t('microdistrictPlaceholder'),\n                              options: _cityLoc!.microdistricts,""",
    "microdistrict searchable placeholder",
)
text = replace_once(
    text,
    """                              decoration: InputDecoration(\n                                labelText: s.t('microdistrictPlaceholder'),\n                                border: const OutlineInputBorder(),\n                              ),""",
    """                              decoration: InputDecoration(\n                                labelText: s.t('microdistrict'),\n                                hintText: s.t('microdistrictPlaceholder'),\n                                border: const OutlineInputBorder(),\n                              ),""",
    "microdistrict text placeholder",
)
text = replace_once(
    text,
    """                              hint: s.t('quartalPlaceholder'),\n                              options: _cityLoc!.quartals,""",
    """                              hint: s.t('quartal'),\n                              placeholder: s.t('quartalPlaceholder'),\n                              options: _cityLoc!.quartals,""",
    "quartal searchable placeholder",
)
text = replace_once(
    text,
    """                              decoration: InputDecoration(\n                                labelText: s.t('quartalPlaceholder'),\n                                border: const OutlineInputBorder(),\n                              ),""",
    """                              decoration: InputDecoration(\n                                labelText: s.t('quartal'),\n                                hintText: s.t('quartalPlaceholder'),\n                                border: const OutlineInputBorder(),\n                              ),""",
    "quartal text placeholder",
)
text = replace_once(
    text,
    """                              hint: s.t('areaPlaceholder'),\n                              options: _cityLoc!.areas,""",
    """                              hint: s.t('areaName'),\n                              placeholder: s.t('areaPlaceholder'),\n                              options: _cityLoc!.areas,""",
    "area searchable placeholder",
)
text = replace_once(
    text,
    """                              decoration: InputDecoration(\n                                labelText: s.t('areaPlaceholder'),\n                                border: const OutlineInputBorder(),\n                              ),""",
    """                              decoration: InputDecoration(\n                                labelText: s.t('areaName'),\n                                hintText: s.t('areaPlaceholder'),\n                                border: const OutlineInputBorder(),\n                              ),""",
    "area text placeholder",
)
text = replace_once(
    text,
    """                        decoration: InputDecoration(\n                          labelText: s.t('metroDistanceHint'),\n                          suffixText: 'm',\n                          border: const OutlineInputBorder(),\n                        ),""",
    """                        decoration: InputDecoration(\n                          labelText: s.t('metroDistance'),\n                          hintText: s.t('metroDistanceHint'),\n                          suffixText: 'm',\n                          border: const OutlineInputBorder(),\n                        ),""",
    "metro distance placeholder",
)
text = replace_once(
    text,
    """                          decoration: InputDecoration(\n                            labelText: s.t('nearbyDistance'),\n                            suffixText: 'm',\n                            border: const OutlineInputBorder(),\n                          ),""",
    """                          decoration: InputDecoration(\n                            labelText: s.t('nearbyDistance'),\n                            hintText: s.t('metroDistanceHint'),\n                            suffixText: 'm',\n                            border: const OutlineInputBorder(),\n                          ),""",
    "nearby distance placeholder",
)
text = replace_once(
    text,
    """                              decoration: InputDecoration(\n                                labelText: s.t('min'),\n                                border: const OutlineInputBorder(),\n                              ),""",
    """                              decoration: InputDecoration(\n                                labelText: s.t('min'),\n                                hintText: s.t('minPlaceholder'),\n                                border: const OutlineInputBorder(),\n                              ),""",
    "price min placeholder",
)
text = replace_once(
    text,
    """                              decoration: InputDecoration(\n                                labelText: s.t('max'),\n                                border: const OutlineInputBorder(),\n                              ),""",
    """                              decoration: InputDecoration(\n                                labelText: s.t('max'),\n                                hintText: s.t('maxPlaceholder'),\n                                border: const OutlineInputBorder(),\n                              ),""",
    "price max placeholder",
)
text = replace_once(
    text,
    """                          decoration: InputDecoration(\n                            labelText: '+ ${s.t('max')}',\n                            prefixText: '+ ',\n                            border: const OutlineInputBorder(),\n                          ),""",
    """                          decoration: InputDecoration(\n                            labelText: '+ ${s.t('max')}',\n                            hintText: '100',\n                            prefixText: '+ ',\n                            border: const OutlineInputBorder(),\n                          ),""",
    "price tolerance placeholder",
)
write(path, text)


# Card action controls: shrink the button background itself to 28x28 while
# growing the glyph to 18. InkWell avoids IconButton's Material minimum target
# from visually inflating the surface again.
path = "app/lib/widgets/listing_card.dart"
text = read(path)
text = text.replace("const SizedBox(width: 6),", "const SizedBox(width: 4),", 2)
buttons_start = "class _FavButton extends StatelessWidget {"
buttons_end = "/// Deal-type label on the photo's top-left corner"
buttons_replacement = """class _FavButton extends StatelessWidget {\n  const _FavButton({\n    required this.isFav,\n    required this.tooltip,\n    required this.onPressed,\n  });\n\n  final bool isFav;\n  final String tooltip;\n  final VoidCallback onPressed;\n\n  @override\n  Widget build(BuildContext context) {\n    final scheme = Theme.of(context).colorScheme;\n    return Tooltip(\n      message: tooltip,\n      child: Material(\n        color: scheme.surfaceContainerHighest,\n        borderRadius: BorderRadius.circular(7),\n        clipBehavior: Clip.antiAlias,\n        child: InkWell(\n          onTap: onPressed,\n          child: SizedBox(\n            width: 28,\n            height: 28,\n            child: Icon(\n              isFav ? Icons.favorite : Icons.favorite_border,\n              size: 18,\n              color: isFav ? Colors.redAccent : scheme.onSurfaceVariant,\n            ),\n          ),\n        ),\n      ),\n    );\n  }\n}\n\nclass _CardActionButton extends StatelessWidget {\n  const _CardActionButton({\n    required this.icon,\n    required this.tooltip,\n    required this.onPressed,\n  });\n\n  final IconData icon;\n  final String tooltip;\n  final VoidCallback? onPressed;\n\n  @override\n  Widget build(BuildContext context) {\n    final scheme = Theme.of(context).colorScheme;\n    return Tooltip(\n      message: tooltip,\n      child: Material(\n        color: scheme.surfaceContainerHighest,\n        borderRadius: BorderRadius.circular(7),\n        clipBehavior: Clip.antiAlias,\n        child: InkWell(\n          onTap: onPressed,\n          child: SizedBox(\n            width: 28,\n            height: 28,\n            child: Icon(icon, size: 18, color: scheme.onSurfaceVariant),\n          ),\n        ),\n      ),\n    );\n  }\n}\n\n"""
text = replace_between(text, buttons_start, buttons_end, buttons_replacement, "card action widgets")
write(path, text)


# Map parity with Personal Site. Replace the old degree-grid / giant price
# bubble logic by screen-space 38px clustering, bounds zooming and a radial
# listing browser for truly coincident points. A standalone point gets a
# price pill only if its full pill rectangle is clear of every other listing
# marker; the pill color comes from the existing PriceTone logic.
path = "app/lib/widgets/map_view.dart"
text = read(path)
text = replace_once(
    text,
    "import 'package:flutter/material.dart';",
    "import 'package:cached_network_image/cached_network_image.dart';\nimport 'package:flutter/material.dart';",
    "map cached image import",
)
text = replace_once(
    text,
    """  // Which page of price pins is showing for each clustered pin group.\n  static const _pageSize = 8;\n  final Map<String, int> _groupPage = {};\n\n  double _zoom = 6;""",
    """  // Same marker behaviour as Personal Site.\n  static const _pageSize = 9;\n  static const _clusterRadiusPx = 38.0;\n  static const _clusterZoomMax = 19.0;\n  static const _priceMarkerWidth = 76.0;\n  static const _priceMarkerHeight = 28.0;\n  final Map<String, int> _groupPage = {};\n\n  double _zoom = 6;\n  String _lastFitSignature = '';""",
    "map cluster fields",
)
text = replace_once(
    text,
    """  bool _showDistricts = true;\n  bool _showMicrodistricts = false;\n  bool _showQuartals = false;\n  bool _showAreas = true;""",
    """  bool _showCity = true;\n  bool _showDistricts = true;\n  bool _showMicrodistricts = false;\n  bool _showQuartals = false;\n  bool _showAreas = true;""",
    "map city toggle state",
)
text = replace_once(
    text,
    """  void initState() {\n    super.initState();\n    _zoom = widget.centerZoom;\n    _loadZones();\n  }""",
    """  void initState() {\n    super.initState();\n    _zoom = widget.centerZoom;\n    _loadZones();\n    _scheduleFitToPoints();\n  }""",
    "map initial fit",
)
text = replace_once(
    text,
    """    // A selected city must open at city scale, not at the country's capital\n    // zoom. A focused listing keeps its explicit close zoom.\n    if (zones.cityZone != null && widget.centerZoom < 10) {\n      _controller.move(LatLng(zones.cityZone!.lat, zones.cityZone!.lng), 11.5);\n    }""",
    """    // The web map frames the actual map feed first. The city centroid is\n    // only a fallback when no located result exists.\n    if (zones.cityZone != null && widget.centerZoom < 10 && _visible.isEmpty) {\n      _controller.move(LatLng(zones.cityZone!.lat, zones.cityZone!.lng), 11.5);\n    }""",
    "map city fallback",
)
text = replace_once(
    text,
    """  void didUpdateWidget(covariant MapView old) {\n    super.didUpdateWidget(old);\n    // Recenter when the country selection changes the center noticeably.\n    if (old.center != widget.center) {\n      _controller.move(widget.center, widget.centerZoom);\n    }\n    if (old.country != widget.country || old.city != widget.city) {\n      _selectedDistrictId = null;\n      _zones = const MapZones();\n      _loadZones();\n    }\n  }""",
    """  void didUpdateWidget(covariant MapView old) {\n    super.didUpdateWidget(old);\n    if (old.center != widget.center || old.centerZoom != widget.centerZoom) {\n      _controller.move(widget.center, widget.centerZoom);\n    }\n    final geographyChanged =\n        old.country != widget.country || old.city != widget.city;\n    if (geographyChanged) {\n      _selectedDistrictId = null;\n      _zones = const MapZones();\n      _loadZones();\n    }\n    if (geographyChanged || !identical(old.listings, widget.listings)) {\n      _scheduleFitToPoints();\n    }\n  }""",
    "map update behavior",
)

cluster_start = "  /// Approximate meters per screen pixel"
cluster_end = "  void _onMapTap(LatLng point) {"
cluster_replacement = r'''  bool get _isFocused => widget.centerZoom >= 17.5;

  String _listingKey(Listing listing) =>
      '${listing.source}:${listing.country}:${listing.id}';

  void _scheduleFitToPoints() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitToPoints();
    });
  }

  /// Matches Personal Site's fitToPoints(): frame the complete compact map
  /// feed once and cap the initial zoom at 14.
  void _fitToPoints() {
    if (_isFocused) return;
    final located = widget.listings.where((listing) => listing.hasLocation).toList();
    if (located.isEmpty) return;
    final keys = located.map(_listingKey).toList()..sort();
    final signature = keys.join(',');
    if (signature == _lastFitSignature) return;
    try {
      _controller.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints([
            for (final listing in located) LatLng(listing.lat!, listing.lng!),
          ]),
          padding: const EdgeInsets.all(30),
          maxZoom: 14,
        ),
      );
      _lastFitSignature = signature;
    } catch (_) {
      // The controller can still be attaching on the very first frame.
    }
  }

  Offset _worldPixel(LatLng point) {
    final worldSize = 256.0 * math.pow(2, _zoom).toDouble();
    final lat = point.latitude.clamp(-85.05112878, 85.05112878).toDouble();
    final sinLat = math.sin(lat * math.pi / 180);
    final x = (point.longitude + 180) / 360 * worldSize;
    final y =
        (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) *
        worldSize;
    return Offset(x, y);
  }

  double _wrappedDx(double a, double b) {
    final worldSize = 256.0 * math.pow(2, _zoom).toDouble();
    final raw = (a - b).abs();
    return math.min(raw, worldSize - raw);
  }

  /// Greedy screen-space clustering, equivalent to FlatMap.client.vue's
  /// latLngToContainerPoint + 38px distance check.
  List<_PinGroup> _groupsFor(List<Listing> located) {
    if (located.isEmpty) return const [];
    final clusters = <_ClusterAccumulator>[];
    for (final listing in located) {
      final point = _worldPixel(LatLng(listing.lat!, listing.lng!));
      _ClusterAccumulator? target;
      for (final cluster in clusters) {
        final dx = _wrappedDx(cluster.x, point.dx);
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

  bool _hasRealSpread(_PinGroup group) {
    final first = group.listings.first;
    return group.listings.skip(1).any(
      (listing) => listing.lat != first.lat || listing.lng != first.lng,
    );
  }

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
      final otherHalfWidth = other.listings.length == 1
          ? _priceMarkerWidth / 2
          : 16.0;
      final otherHalfHeight = other.listings.length == 1
          ? _priceMarkerHeight / 2
          : 16.0;
      if (dx < _priceMarkerWidth / 2 + otherHalfWidth + 4 &&
          dy < _priceMarkerHeight / 2 + otherHalfHeight + 4) {
        return false;
      }
    }
    return true;
  }

  void _openGroup(_PinGroup group) {
    if (group.listings.length == 1) {
      widget.onTapListing(group.listings.first);
      return;
    }
    if (_hasRealSpread(group) && _zoom < _clusterZoomMax - 0.01) {
      setState(() => _expandedGroupKey = null);
      try {
        _controller.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints([
              for (final listing in group.listings)
                LatLng(listing.lat!, listing.lng!),
            ]),
            padding: const EdgeInsets.all(40),
            maxZoom: _clusterZoomMax,
          ),
        );
      } catch (_) {}
      return;
    }
    setState(() {
      _expandedGroupKey = group.key;
      _groupPage[group.key] = 0;
    });
  }

  List<Marker> _markersForGroup(_PinGroup group, List<_PinGroup> groups) {
    if (group.listings.length == 1 && _canShowStandalonePrice(group, groups)) {
      final listing = group.listings.first;
      return [
        Marker(
          point: group.point,
          width: _priceMarkerWidth,
          height: _priceMarkerHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onTapListing(listing),
            child: _StandalonePricePin(
              listing: listing,
              rates: widget.rates,
              displayCurrency: widget.displayCurrency,
            ),
          ),
        ),
      ];
    }

    final size = group.listings.length > 1 ? 32.0 : 16.0;
    return [
      Marker(
        point: group.point,
        width: size,
        height: size,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openGroup(group),
          child: _ClusterDot(count: group.listings.length),
        ),
      ),
    ];
  }

  _PinGroup? _expandedGroup(List<_PinGroup> groups) {
    final key = _expandedGroupKey;
    if (key == null) return null;
    for (final group in groups) {
      if (group.key == key) return group;
    }
    return null;
  }

  Marker _radialMarkerForGroup(_PinGroup group) {
    final pageCount = (group.listings.length / _pageSize).ceil();
    final current = _groupPage[group.key] ?? 0;
    final pageIndex = current % pageCount;
    final start = pageIndex * _pageSize;
    final end = math.min(start + _pageSize, group.listings.length);
    return Marker(
      point: group.point,
      width: 280,
      height: 280,
      child: _RadialClusterMarker(
        items: group.listings.sublist(start, end),
        pageIndex: pageIndex,
        pageCount: pageCount,
        rates: widget.rates,
        displayCurrency: widget.displayCurrency,
        onTapListing: widget.onTapListing,
        onClose: () => setState(() => _expandedGroupKey = null),
        onPrev: pageCount <= 1
            ? null
            : () => setState(
                  () => _groupPage[group.key] =
                      (pageIndex - 1 + pageCount) % pageCount,
                ),
        onNext: pageCount <= 1
            ? null
            : () => setState(
                  () => _groupPage[group.key] = (pageIndex + 1) % pageCount,
                ),
      ),
    );
  }

'''
text = replace_between(text, cluster_start, cluster_end, cluster_replacement, "map clustering block")
text = replace_once(
    text,
    """  void _onMapTap(LatLng point) {\n    if (_drawing) {""",
    """  void _onMapTap(LatLng point) {\n    if (_expandedGroupKey != null) {\n      setState(() => _expandedGroupKey = null);\n    }\n    if (_drawing) {""",
    "map tap closes radial",
)
text = replace_once(
    text,
    """    final s = context.watch<SettingsState>().s;\n    final visible = _visible;\n    return Stack(""",
    """    final s = context.watch<SettingsState>().s;\n    final visible = _visible;\n    final groups = _groupsFor(visible);\n    final expandedGroup = _expandedGroup(groups);\n    return Stack(""",
    "map build groups",
)
text = replace_once(
    text,
    """            minZoom: 2,\n            maxZoom: 18,\n            onTap: (_, point) => _onMapTap(point),\n            onPositionChanged: (position, hasGesture) {\n              final z = position.zoom;\n              if ((z - _zoom).abs() > 0.05) setState(() => _zoom = z);\n            },""",
    """            minZoom: 2,\n            maxZoom: 19,\n            onTap: (_, point) => _onMapTap(point),\n            onPositionChanged: (position, hasGesture) {\n              final z = position.zoom;\n              final zoomChanged = (z - _zoom).abs() > 0.05;\n              final closeRadial = hasGesture && _expandedGroupKey != null;\n              if (zoomChanged || closeRadial) {\n                setState(() {\n                  _zoom = z;\n                  _expandedGroupKey = null;\n                });\n              }\n            },""",
    "map camera updates",
)
text = replace_once(
    text,
    """            if (_showAreas && _zones.areaZones.isNotEmpty)\n              PolygonLayer(""",
    """            if (_showCity &&\n                _zones.cityZone?.boundaryRings.isNotEmpty == true)\n              PolygonLayer(\n                polygons: [\n                  for (final ring in _zones.cityZone!.boundaryRings)\n                    Polygon(\n                      points: ring,\n                      borderStrokeWidth: 2,\n                      borderColor: _parseHexColor(\n                        _zones.cityZone!.colorHex,\n                      ).withValues(alpha: 0.55),\n                      color: Colors.transparent,\n                    ),\n                ],\n              ),\n            if (_showAreas && _zones.areaZones.isNotEmpty)\n              PolygonLayer(""",
    "map city boundary",
)
text = replace_once(
    text,
    """            MarkerLayer(\n              markers: [\n                for (final group in _groupsFor(visible))\n                  ..._markersForGroup(group),\n              ],\n            ),""",
    """            MarkerLayer(\n              markers: [\n                for (final group in groups) ..._markersForGroup(group, groups),\n                if (expandedGroup != null) _radialMarkerForGroup(expandedGroup),\n                if (_isFocused)\n                  Marker(\n                    point: widget.center,\n                    width: 44,\n                    height: 44,\n                    child: const _FocusMarker(),\n                  ),\n              ],\n            ),""",
    "map marker layer",
)
text = replace_once(
    text,
    """        if (_zones.districtZones.isNotEmpty ||\n            _zones.microdistrictMarkers.isNotEmpty ||""",
    """        if (_zones.cityZone?.boundaryRings.isNotEmpty == true ||\n            _zones.districtZones.isNotEmpty ||\n            _zones.microdistrictMarkers.isNotEmpty ||""",
    "map toolbar condition",
)
text = replace_once(
    text,
    """                children: [\n                  if (_zones.districtZones.isNotEmpty)\n                    _ZoneToggle(""",
    """                children: [\n                  if (_zones.cityZone?.boundaryRings.isNotEmpty == true)\n                    _ZoneToggle(\n                      label: s.t('city'),\n                      active: _showCity,\n                      onTap: () => setState(() => _showCity = !_showCity),\n                    ),\n                  if (_zones.districtZones.isNotEmpty)\n                    _ZoneToggle(""",
    "map city layer toggle",
)

tail_start = "/// Listings that share (almost) the same coordinate"
tail_replacement = r'''class _ClusterAccumulator {
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

class _PinGroup {
  const _PinGroup(this.key, this.listings, this.point);
  final String key;
  final List<Listing> listings;
  final LatLng point;
}

class _ClusterDot extends StatelessWidget {
  const _ClusterDot({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: count > 1 ? 0.92 : 1),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3)],
      ),
      child: count > 1
          ? Text(
              count > 999 ? '999+' : '$count',
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            )
          : null,
    );
  }
}

class _StandalonePricePin extends StatelessWidget {
  const _StandalonePricePin({
    required this.listing,
    this.rates,
    this.displayCurrency,
  });

  final Listing listing;
  final Map<String, double>? rates;
  final String? displayCurrency;

  @override
  Widget build(BuildContext context) {
    final ratesOrEmpty = rates ?? const <String, double>{};
    final label = pinPriceLabel(
      listing,
      rates: rates,
      displayCurrency: displayCurrency,
    );
    final color = priceToneColor(listingPriceTone(listing, ratesOrEmpty));
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          shadows: [Shadow(color: Colors.black38, blurRadius: 2)],
        ),
      ),
    );
  }
}

class _FocusMarker extends StatelessWidget {
  const _FocusMarker();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.58), width: 2),
          ),
        ),
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.95),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
          ),
        ),
      ],
    );
  }
}

class _RadialClusterMarker extends StatelessWidget {
  const _RadialClusterMarker({
    required this.items,
    required this.pageIndex,
    required this.pageCount,
    required this.rates,
    required this.displayCurrency,
    required this.onTapListing,
    required this.onClose,
    this.onPrev,
    this.onNext,
  });

  final List<Listing> items;
  final int pageIndex;
  final int pageCount;
  final Map<String, double>? rates;
  final String? displayCurrency;
  final void Function(Listing) onTapListing;
  final VoidCallback onClose;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    const size = 280.0;
    const center = size / 2;
    final radius = items.length <= 4 ? 72.0 : 94.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < items.length; i++)
            () {
              final angle =
                  (-90 + (360 / math.max(1, items.length)) * i) *
                  math.pi /
                  180;
              return Positioned(
                left: center + math.cos(angle) * radius - 38,
                top: center + math.sin(angle) * radius - 32,
                child: _RadialTab(
                  listing: items[i],
                  rates: rates,
                  displayCurrency: displayCurrency,
                  onTap: () => onTapListing(items[i]),
                ),
              );
            }(),
          Positioned(
            left: center - 26,
            top: center - 26,
            child: _RadialHub(
              label: '${pageIndex + 1}/$pageCount',
              onClose: onClose,
              onPrev: onPrev,
              onNext: onNext,
            ),
          ),
        ],
      ),
    );
  }
}

class _RadialHub extends StatelessWidget {
  const _RadialHub({
    required this.label,
    required this.onClose,
    this.onPrev,
    this.onNext,
  });

  final String label;
  final VoidCallback onClose;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          _RadialArrow(icon: Icons.chevron_left, onTap: onPrev),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClose,
              child: Center(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          _RadialArrow(icon: Icons.chevron_right, onTap: onNext),
        ],
      ),
    );
  }
}

class _RadialArrow extends StatelessWidget {
  const _RadialArrow({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.35 : 1,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 15,
          height: 52,
          child: Icon(icon, size: 20, color: Colors.white),
        ),
      ),
    );
  }
}

class _RadialTab extends StatelessWidget {
  const _RadialTab({
    required this.listing,
    required this.rates,
    required this.displayCurrency,
    required this.onTap,
  });

  final Listing listing;
  final Map<String, double>? rates;
  final String? displayCurrency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final photo = listing.photo ??
        (listing.photos.isNotEmpty ? listing.photos.first : null);
    final price = pinPriceLabel(
      listing,
      rates: rates,
      displayCurrency: displayCurrency,
    );
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(7),
      clipBehavior: Clip.antiAlias,
      elevation: 6,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 76,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 76,
                height: 46,
                child: photo == null
                    ? Icon(
                        Icons.home_outlined,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.45),
                      )
                    : CachedNetworkImage(
                        imageUrl: photo,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => ColoredBox(
                          color: scheme.surfaceContainerHighest,
                        ),
                        errorWidget: (_, __, ___) => Icon(
                          Icons.home_outlined,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.45),
                        ),
                      ),
              ),
              SizedBox(
                height: 18,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Center(
                    child: Text(
                      price,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
'''
text = replace_tail(text, tail_start, tail_replacement, "map helper tail")
write(path, text)


# Focus-on-listing uses the same zoom as Personal Site (FOCUS_ZOOM = 18).
path = "app/lib/screens/home_screen.dart"
text = read(path)
needle = "_focusListing?.hasLocation == true ? 15 : 6"
count = text.count(needle)
if count != 2:
    raise SystemExit(f"focus zoom: expected 2 matches, got {count}")
text = text.replace(needle, "_focusListing?.hasLocation == true ? 18 : 6")
write(path, text)


# Keep the compact 48px field sizing in light mode too; otherwise 'all inputs'
# was only true in dark/dark-blue themes.
path = "app/lib/state/settings.dart"
text = read(path)
light_anchor = """        outlinedButtonTheme: OutlinedButtonThemeData(\n          style: OutlinedButton.styleFrom(\n            minimumSize: const Size(0, 40),\n            padding: const EdgeInsets.symmetric(horizontal: 16),\n          ),\n        ),\n      );"""
light_replacement = """        outlinedButtonTheme: OutlinedButtonThemeData(\n          style: OutlinedButton.styleFrom(\n            minimumSize: const Size(0, 40),\n            padding: const EdgeInsets.symmetric(horizontal: 16),\n          ),\n        ),\n        inputDecorationTheme: _brandInputTheme(BrandColors.primary),\n      );"""
# Only the light branch lacks this theme; the exact anchor appears once there.
text = replace_once(text, light_anchor, light_replacement, "light input theme")
write(path, text)

import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/district_zone.dart';
import '../models/listing.dart';
import '../services/api_service.dart';
import '../state/settings.dart';
import '../utils/format.dart';
import '../utils/price_tone.dart';

/// Same district colours as whiteslove.me's map (`useDistrictZones.ts`
/// ZONE_PALETTE) — kept only as a fallback for zones whose stored colour
/// string fails to parse.
const _fallbackZoneColor = Color(0xFFE0679A);

Color _parseHexColor(String hex) {
  final cleaned = hex.replaceFirst('#', '');
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) return _fallbackZoneColor;
  return Color(0xFF000000 | value);
}

/// Desaturates a colour to approximate the site's `filter: grayscale(0.85)`
/// on unselected districts once one district is selected.
Color _desaturate(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withSaturation(hsl.saturation * (1 - amount)).toColor();
}

class MapView extends StatefulWidget {
  const MapView({
    super.key,
    required this.listings,
    required this.center,
    required this.onTapListing,
    this.rates,
    this.displayCurrency,
    this.country = '',
    this.city = '',
    this.centerZoom = 6,
    this.onExpand,
  });

  final List<Listing> listings;
  final LatLng center;
  final void Function(Listing) onTapListing;
  final Map<String, double>? rates;
  final String? displayCurrency;
  final String country;
  final String city;

  /// Shows a "view full-screen" button (top-right, next to the draw
  /// controls) when set — the compact in-page map passes a callback that
  /// pushes a full-screen route; the full-screen route itself passes null so
  /// the button doesn't show a second time.
  final VoidCallback? onExpand;

  /// Zoom level used when [center] changes (e.g. 6 for a country default,
  /// higher when a specific listing's "show on map" set the center).
  final double centerZoom;

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  final MapController _controller = MapController();
  final ApiService _api = ApiService();

  // Freeform search area the user outlines by tapping the map.
  bool _drawing = false;
  final List<LatLng> _area = [];

  // Same marker behaviour as Personal Site.
  static const _pageSize = 9;
  static const _clusterRadiusPx = 38.0;
  static const _clusterZoomMax = 19.0;
  static const _priceMarkerWidth = 76.0;
  static const _priceMarkerHeight = 28.0;
  final Map<String, int> _groupPage = {};

  double _zoom = 6;
  String _lastFitSignature = '';

  // Colour overlay layers, matching the site's map + its toolbar toggles.
  MapZones _zones = const MapZones();
  String? _selectedDistrictId;
  // Defaults match the site's useShow*() refs in FlatMap.client.vue.
  bool _showCity = true;
  bool _showDistricts = true;
  bool _showMicrodistricts = false;
  bool _showQuartals = false;
  bool _showAreas = true;

  @override
  void initState() {
    super.initState();
    _zoom = widget.centerZoom;
    _loadZones();
    _scheduleFitToPoints();
  }

  Future<void> _loadZones() async {
    if (widget.country.isEmpty || widget.city.isEmpty) return;
    final zones = await _api.fetchMapZones(widget.country, widget.city);
    if (!mounted) return;
    setState(() => _zones = zones);
    // The web map frames the actual map feed first. The city centroid is
    // only a fallback when no located result exists.
    if (zones.cityZone != null && widget.centerZoom < 10 && _visible.isEmpty) {
      _controller.move(LatLng(zones.cityZone!.lat, zones.cityZone!.lng), 11.5);
    }
  }

  @override
  void didUpdateWidget(covariant MapView old) {
    super.didUpdateWidget(old);
    if (old.center != widget.center || old.centerZoom != widget.centerZoom) {
      _controller.move(widget.center, widget.centerZoom);
    }
    final geographyChanged =
        old.country != widget.country || old.city != widget.city;
    if (geographyChanged) {
      _selectedDistrictId = null;
      _zones = const MapZones();
      _loadZones();
    }
    if (geographyChanged || !identical(old.listings, widget.listings)) {
      _scheduleFitToPoints();
    }
  }

  /// A closed ring approximating a circle, for zones with no real boundary
  /// polygon from the catalog (matches the site's Leaflet circle fallback).
  List<LatLng> _circleRing(DistrictZone zone) {
    const points = 48;
    final latRad = zone.lat * math.pi / 180;
    final dLat = zone.radiusM / 111320;
    final dLng = zone.radiusM / (111320 * math.cos(latRad));
    return [
      for (var i = 0; i <= points; i++)
        LatLng(
          zone.lat + dLat * math.sin(2 * math.pi * i / points),
          zone.lng + dLng * math.cos(2 * math.pi * i / points),
        ),
    ];
  }

  List<List<LatLng>> _ringsFor(DistrictZone zone) =>
      zone.boundaryRings.isNotEmpty ? zone.boundaryRings : [_circleRing(zone)];

  void _onDistrictTap(String id) {
    setState(() => _selectedDistrictId = _selectedDistrictId == id ? null : id);
  }

  void _showZoneName(String name) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(name), duration: const Duration(seconds: 2)),
      );
  }

  /// Listings restricted to the drawn area (once it has at least 3 points).
  List<Listing> get _visible {
    final located = widget.listings.where((l) => l.hasLocation).toList();
    if (_area.length < 3) return located;
    return located
        .where((l) => _pointInPolygon(LatLng(l.lat!, l.lng!), _area))
        .toList();
  }

  // Ray-casting point-in-polygon test on lat/lng.
  bool _pointInPolygon(LatLng p, List<LatLng> poly) {
    bool inside = false;
    for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final xi = poly[i].longitude, yi = poly[i].latitude;
      final xj = poly[j].longitude, yj = poly[j].latitude;
      final intersect =
          ((yi > p.latitude) != (yj > p.latitude)) &&
          (p.longitude < (xj - xi) * (p.latitude - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  bool get _isFocused => widget.centerZoom >= 17.5;

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
    final located = widget.listings
        .where((listing) => listing.hasLocation)
        .toList();
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
    return group.listings
        .skip(1)
        .any((listing) => listing.lat != first.lat || listing.lng != first.lng);
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

  void _onMapTap(LatLng point) {
    if (_expandedGroupKey != null) {
      setState(() => _expandedGroupKey = null);
    }
    if (_drawing) {
      setState(() => _area.add(point));
      return;
    }
    // Tapping a district selects it (dimming the rest); tapping empty map
    // clears the selection — same behavior as the site's map.
    if (_showDistricts) {
      for (final zone in _zones.districtZones) {
        for (final ring in _ringsFor(zone)) {
          if (_pointInPolygon(point, ring)) {
            _onDistrictTap(zone.id);
            return;
          }
        }
      }
    }
    if (_selectedDistrictId != null) setState(() => _selectedDistrictId = null);
  }

  void _clearArea() => setState(() => _area.clear());

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsState>().s;
    final visible = _visible;
    final groups = _groupsFor(visible);
    final expandedGroup = _expandedGroup(groups);
    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: widget.center,
            initialZoom: widget.centerZoom,
            minZoom: 2,
            maxZoom: 19,
            onTap: (_, point) => _onMapTap(point),
            onPositionChanged: (position, hasGesture) {
              final z = position.zoom;
              final zoomChanged = (z - _zoom).abs() > 0.05;
              final closeRadial = hasGesture && _expandedGroupKey != null;
              if (zoomChanged || closeRadial) {
                setState(() {
                  _zoom = z;
                  _expandedGroupKey = null;
                });
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.flat_finder',
              maxZoom: 19,
            ),
            if (_showCity && _zones.cityZone?.boundaryRings.isNotEmpty == true)
              PolygonLayer(
                polygons: [
                  for (final ring in _zones.cityZone!.boundaryRings)
                    Polygon(
                      points: ring,
                      borderStrokeWidth: 2,
                      borderColor: _parseHexColor(_zones.cityZone!.colorHex)
                          .withValues(alpha: 0.55),
                      color: Colors.transparent,
                    ),
                ],
              ),
            if (_showAreas && _zones.areaZones.isNotEmpty)
              PolygonLayer(
                polygons: [
                  for (final zone in _zones.areaZones)
                    for (final ring in _ringsFor(zone))
                      () {
                        final color = _parseHexColor(zone.colorHex);
                        return Polygon(
                          points: ring,
                          borderStrokeWidth: 2,
                          borderColor: color.withValues(alpha: 0.6),
                          color: color.withValues(alpha: 0.14),
                        );
                      }(),
                ],
              ),
            if (_showDistricts && _zones.districtZones.isNotEmpty)
              PolygonLayer(
                polygons: [
                  for (final zone in _zones.districtZones)
                    for (final ring in _ringsFor(zone))
                      () {
                        final dimmed =
                            _selectedDistrictId != null &&
                            zone.id != _selectedDistrictId;
                        final base = _parseHexColor(zone.colorHex);
                        final color = dimmed ? _desaturate(base, 0.85) : base;
                        return Polygon(
                          points: ring,
                          borderStrokeWidth: 2.5,
                          borderColor: color.withValues(
                            alpha: dimmed ? 0.5 : 0.9,
                          ),
                          color: color.withValues(alpha: dimmed ? 0.08 : 0.22),
                        );
                      }(),
                ],
              ),
            if (_showDistricts && _zones.districtZones.isNotEmpty)
              MarkerLayer(
                markers: [
                  for (final zone in _zones.districtZones)
                    Marker(
                      point: LatLng(zone.lat, zone.lng),
                      width: 120,
                      height: 24,
                      child: IgnorePointer(
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color:
                                    (_selectedDistrictId != null &&
                                        zone.id != _selectedDistrictId)
                                    ? _desaturate(
                                        _parseHexColor(zone.colorHex),
                                        0.85,
                                      ).withValues(alpha: 0.55)
                                    : _parseHexColor(zone.colorHex),
                              ),
                            ),
                            child: Text(
                              zone.name,
                              style: TextStyle(
                                color: Colors.white.withValues(
                                  alpha:
                                      (_selectedDistrictId != null &&
                                          zone.id != _selectedDistrictId)
                                      ? 0.55
                                      : 1,
                                ),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            if (_showMicrodistricts && _zones.microdistrictMarkers.isNotEmpty)
              MarkerLayer(
                markers: [
                  for (final zone in _zones.microdistrictMarkers)
                    Marker(
                      point: LatLng(zone.lat, zone.lng),
                      width: 14,
                      height: 14,
                      child: GestureDetector(
                        onTap: () => _showZoneName(zone.name),
                        child: _ZoneDot(
                          colorHex: zone.colorHex,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            if (_showQuartals && _zones.quartalMarkers.isNotEmpty)
              MarkerLayer(
                markers: [
                  for (final zone in _zones.quartalMarkers)
                    Marker(
                      point: LatLng(zone.lat, zone.lng),
                      width: 14,
                      height: 14,
                      child: GestureDetector(
                        onTap: () => _showZoneName(zone.name),
                        child: _ZoneDot(
                          colorHex: zone.colorHex,
                          shape: BoxShape.rectangle,
                        ),
                      ),
                    ),
                ],
              ),
            if (_area.length >= 3)
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: _area,
                    borderStrokeWidth: 2,
                    borderColor: Theme.of(context).colorScheme.primary,
                    color: Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.15),
                  ),
                ],
              ),
            if (_area.length >= 2 && _area.length < 3)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _area,
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            if (_drawing)
              MarkerLayer(
                markers: [
                  for (final pt in _area)
                    Marker(
                      point: pt,
                      width: 14,
                      height: 14,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
            MarkerLayer(
              markers: [
                for (final group in groups) ..._markersForGroup(group, groups),
                if (expandedGroup != null) _radialMarkerForGroup(expandedGroup),
                if (_isFocused)
                  Marker(
                    point: widget.center,
                    width: 44,
                    height: 44,
                    child: const _FocusMarker(),
                  ),
              ],
            ),
            const RichAttributionWidget(
              attributions: [
                TextSourceAttribution('© OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
        // Draw controls.
        Positioned(
          top: 12,
          right: 12,
          child: Column(
            children: [
              if (widget.onExpand != null) ...[
                FloatingActionButton.small(
                  heroTag: 'expand',
                  onPressed: widget.onExpand,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  child: const Icon(Icons.fullscreen),
                ),
                const SizedBox(height: 8),
              ],
              FloatingActionButton.small(
                heroTag: 'draw',
                onPressed: () => setState(() => _drawing = !_drawing),
                backgroundColor: _drawing
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.surface,
                foregroundColor: _drawing
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurface,
                child: Icon(_drawing ? Icons.check : Icons.gesture),
              ),
              if (_area.isNotEmpty) ...[
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'clearArea',
                  onPressed: _clearArea,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  child: const Icon(Icons.delete_outline),
                ),
              ],
            ],
          ),
        ),
        // Hint while drawing, or a count once an area is applied.
        if (_drawing || _area.length >= 3)
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _area.length >= 3
                    ? s.t('inArea', {'n': '${visible.length}'})
                    : s.t('drawHint'),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        // District/microdistrict/quartal/area layer toggles — same toolbar
        // as the site's map, each shown only when that layer has data. Kept
        // near the top (below the draw hint) instead of hovering over the
        // bottom of the map, which is easy to reach but easy to miss.
        if (_zones.cityZone?.boundaryRings.isNotEmpty == true ||
            _zones.districtZones.isNotEmpty ||
            _zones.microdistrictMarkers.isNotEmpty ||
            _zones.quartalMarkers.isNotEmpty ||
            _zones.areaZones.isNotEmpty)
          Positioned(
            left: 12,
            right: 68,
            top: _drawing || _area.length >= 3 ? 56 : 12,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (_zones.cityZone?.boundaryRings.isNotEmpty == true)
                    _ZoneToggle(
                      label: s.t('city'),
                      active: _showCity,
                      onTap: () => setState(() => _showCity = !_showCity),
                    ),
                  if (_zones.districtZones.isNotEmpty)
                    _ZoneToggle(
                      label: s.t('districts'),
                      active: _showDistricts,
                      onTap: () =>
                          setState(() => _showDistricts = !_showDistricts),
                    ),
                  if (_zones.microdistrictMarkers.isNotEmpty)
                    _ZoneToggle(
                      label: s.t('microdistricts'),
                      active: _showMicrodistricts,
                      onTap: () => setState(
                        () => _showMicrodistricts = !_showMicrodistricts,
                      ),
                    ),
                  if (_zones.quartalMarkers.isNotEmpty)
                    _ZoneToggle(
                      label: s.t('quartals'),
                      active: _showQuartals,
                      onTap: () =>
                          setState(() => _showQuartals = !_showQuartals),
                    ),
                  if (_zones.areaZones.isNotEmpty)
                    _ZoneToggle(
                      label: s.t('areas'),
                      active: _showAreas,
                      onTap: () => setState(() => _showAreas = !_showAreas),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One toggle button in the layer toolbar (District/Microdistrict/Quartal/
/// Area) — same active/inactive states as the site's `.flat-map__tool`.
class _ZoneToggle extends StatelessWidget {
  const _ZoneToggle({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? scheme.primary
                : Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? scheme.primary : Colors.white24),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? scheme.onPrimary : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// A small circle/square dot marking a microdistrict or quartal (mahalla)
/// centroid — matches the site's `flat-zone-marker_circle`/`_square` dots.
class _ZoneDot extends StatelessWidget {
  const _ZoneDot({required this.colorHex, required this.shape});
  final String colorHex;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _parseHexColor(colorHex),
        shape: shape,
        borderRadius: shape == BoxShape.rectangle
            ? BorderRadius.circular(3)
            : null,
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 2)],
      ),
    );
  }
}

class _ClusterAccumulator {
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
                  (-90 + (360 / math.max(1, items.length)) * i) * math.pi / 180;
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
    final photo =
        listing.photo ??
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
                        placeholder: (_, __) =>
                            ColoredBox(color: scheme.surfaceContainerHighest),
                        errorWidget: (_, __, ___) => Icon(
                          Icons.home_outlined,
                          color: scheme.onSurfaceVariant.withValues(
                            alpha: 0.45,
                          ),
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

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/district_zone.dart';
import '../models/listing.dart';
import '../services/api_service.dart';
import '../state/settings.dart';
import '../utils/format.dart';

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
  });

  final List<Listing> listings;
  final LatLng center;
  final void Function(Listing) onTapListing;
  final Map<String, double>? rates;
  final String? displayCurrency;
  final String country;
  final String city;

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

  // Colour overlay layers, matching the site's map + its toolbar toggles.
  MapZones _zones = const MapZones();
  String? _selectedDistrictId;
  // Defaults match the site's useShow*() refs in FlatMap.client.vue.
  bool _showDistricts = true;
  bool _showMicrodistricts = false;
  bool _showQuartals = false;
  bool _showAreas = true;

  @override
  void initState() {
    super.initState();
    _loadZones();
  }

  Future<void> _loadZones() async {
    if (widget.country.isEmpty || widget.city.isEmpty) return;
    final zones = await _api.fetchMapZones(widget.country, widget.city);
    if (!mounted) return;
    setState(() => _zones = zones);
    // A selected city must open at city scale, not at the country's capital
    // zoom. A focused listing keeps its explicit close zoom.
    if (zones.cityZone != null && widget.centerZoom < 10) {
      _controller.move(LatLng(zones.cityZone!.lat, zones.cityZone!.lng), 11.5);
    }
  }

  @override
  void didUpdateWidget(covariant MapView old) {
    super.didUpdateWidget(old);
    // Recenter when the country selection changes the center noticeably.
    if (old.center != widget.center) {
      _controller.move(widget.center, widget.centerZoom);
    }
    if (old.country != widget.country || old.city != widget.city) {
      _selectedDistrictId = null;
      _zones = const MapZones();
      _loadZones();
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

  /// Groups listings that share (almost) the same coordinate, matching the
  /// site's map markers: a lone listing gets a plain price pin, a cluster
  /// gets one circular bubble that pages through its members with arrows
  /// instead of scattering separate pins on top of each other.
  List<_PinGroup> _spread(List<Listing> located) {
    final groups = <String, List<Listing>>{};
    for (final l in located) {
      final key = '${l.lat!.toStringAsFixed(3)},${l.lng!.toStringAsFixed(3)}';
      groups.putIfAbsent(key, () => []).add(l);
    }
    return [
      for (final group in groups.values)
        _PinGroup(group, LatLng(group.first.lat!, group.first.lng!)),
    ];
  }

  void _onMapTap(LatLng point) {
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
    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: widget.center,
            initialZoom: widget.centerZoom,
            minZoom: 2,
            maxZoom: 18,
            onTap: (_, point) => _onMapTap(point),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.flat_finder',
              maxZoom: 19,
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
                for (final group in _spread(visible))
                  Marker(
                    point: group.point,
                    width: group.listings.length > 1 ? 96 : 76,
                    height: 32,
                    child: _PricePinBubble(
                      listings: group.listings,
                      rates: widget.rates,
                      displayCurrency: widget.displayCurrency,
                      onTapListing: widget.onTapListing,
                    ),
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
        // as the site's map, each shown only when that layer has data.
        if (_zones.districtZones.isNotEmpty ||
            _zones.microdistrictMarkers.isNotEmpty ||
            _zones.quartalMarkers.isNotEmpty ||
            _zones.areaZones.isNotEmpty)
          Positioned(
            left: 12,
            right: 12,
            bottom: 82,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
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

/// Listings that share (almost) the same coordinate, plus the point the
/// group's marker is drawn at.
class _PinGroup {
  const _PinGroup(this.listings, this.point);
  final List<Listing> listings;
  final LatLng point;
}

/// A circular price bubble, matching the site's map marker style. A single
/// listing renders as a plain pill; a cluster renders as a circle with the
/// current member's price and left/right arrows to page through the group.
class _PricePinBubble extends StatefulWidget {
  const _PricePinBubble({
    required this.listings,
    required this.onTapListing,
    this.rates,
    this.displayCurrency,
  });

  final List<Listing> listings;
  final void Function(Listing) onTapListing;
  final Map<String, double>? rates;
  final String? displayCurrency;

  @override
  State<_PricePinBubble> createState() => _PricePinBubbleState();
}

class _PricePinBubbleState extends State<_PricePinBubble> {
  int _index = 0;

  void _page(int delta) {
    setState(
      () => _index = (_index + delta) % widget.listings.length < 0
          ? widget.listings.length - 1
          : (_index + delta) % widget.listings.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listings[_index];
    final color = listing.byAgency
        ? BrandColors.toneOrange
        : Theme.of(context).colorScheme.primary;
    final label = pinPriceLabel(
      listing,
      rates: widget.rates,
      displayCurrency: widget.displayCurrency,
    );

    if (widget.listings.length == 1) {
      return GestureDetector(
        onTap: () => widget.onTapListing(listing),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PinArrow(icon: Icons.chevron_left, onTap: () => _page(-1)),
        GestureDetector(
          onTap: () => widget.onTapListing(listing),
          child: Container(
            width: 44,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 3),
              ],
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 9,
              ),
            ),
          ),
        ),
        _PinArrow(icon: Icons.chevron_right, onTap: () => _page(1)),
      ],
    );
  }
}

class _PinArrow extends StatelessWidget {
  const _PinArrow({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 14, color: Colors.white),
      ),
    );
  }
}

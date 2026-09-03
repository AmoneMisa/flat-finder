import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/district_zone.dart';
import '../models/filters.dart';
import '../models/map_listing_point.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
import '../utils/metro_proximity.dart' hide normalizeBearing;
import '../state/settings.dart';
import '../utils/format.dart';
import '../utils/map_group_pagination.dart';
import '../utils/price_tone.dart';
import '../utils/screen_space_clustering.dart';

/// Same district colours as whiteslove.me's map (`useDistrictZones.ts`
/// ZONE_PALETTE) — kept only as a fallback for zones whose stored colour
/// string fails to parse.
const _fallbackZoneColor = Color(0xFFE0679A);
const _metro200Color = Color(0xFF10B981);
const _metro500Color = Color(0xFFD99A0B);
const _metro1000Color = Color(0xFF8B5CF6);
// The chosen wedge's own color, distinct from the three discovery-mode
// presets above -- matches the pink accent the web client's equivalent
// shape uses.
const _metroSelectedColor = Color(0xFFE0679A);

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
    this.locale = '',
    this.centerZoom = 6,
    this.onExpand,
    this.radiusCenter,
    this.radiusM,
    this.onRadiusCenterChanged,
    this.onRadiusChanged,
    this.showBaseTiles = true,
  });

  final List<MapListingPoint> listings;
  final LatLng center;
  final void Function(MapListingPoint) onTapListing;
  final Map<String, double>? rates;
  final String? displayCurrency;
  final String country;
  final String city;
  final String locale;

  /// Shows a "view full-screen" button (top-right, next to the draw
  /// controls) when set — the compact in-page map passes a callback that
  /// pushes a full-screen route; the full-screen route itself passes null so
  /// the button doesn't show a second time.
  final VoidCallback? onExpand;
  final LatLng? radiusCenter;
  final double? radiusM;
  final ValueChanged<LatLng>? onRadiusCenterChanged;
  final ValueChanged<double>? onRadiusChanged;

  /// Can be disabled by widget tests that exercise marker interactions without
  /// making network requests for OpenStreetMap tiles.
  final bool showBaseTiles;

  /// Zoom level used when [center] changes (e.g. 6 for a country default,
  /// higher when a specific listing's "show on map" set the center).
  final double centerZoom;

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> with SingleTickerProviderStateMixin {
  final MapController _controller = MapController();
  final ApiService _api = ApiService();
  late final AnimationController _cameraAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..addListener(_onCameraAnimTick);

  // Freeform search area the user outlines by tapping the map.
  bool _drawing = false;
  bool _placingRadiusCenter = false;
  final List<LatLng> _area = [];

  // The metro wedge's drag handles need to convert a raw touch position into
  // a LatLng, which requires this box's own render geometry (see
  // _globalToLatLng) -- the same technique flutter_map's own "Draggable
  // Marker" example uses, since Marker itself has no native drag support.
  final GlobalKey _mapAreaKey = GlobalKey();
  // Which handle (if any) is currently held, and its in-progress value. Kept
  // separate from AppState so a drag repaints only this widget every frame
  // instead of the whole filter/search pipeline; only the value on release
  // (_onMetroHandleEnd) is worth a search request.
  String? _draggingMetroHandle;
  num? _draftMetroRadiusM;
  num? _draftMetroBearingFrom;
  num? _draftMetroBearingTo;

  // Same marker behaviour as Personal Site.
  static const _radialCapacity = 10;
  static const _clusterRadiusPx = 38.0;
  static const _priceMarkerWidth = 76.0;
  static const _priceMarkerHeight = 28.0;

  double _zoom = 6;
  String _lastFitSignature = '';

  // Screen-space clustering is the most expensive part of every build. A
  // pinch-zoom gesture fires many onPositionChanged updates in quick
  // succession, so the raw zoom is bucketed before it invalidates the cache —
  // this keeps rebuilds during a gesture cheap without changing the clusters
  // actually shown at rest.
  List<_PinGroup>? _groupsCache;
  String? _groupsCacheKey;

  // Canonical geography overlay layers.
  MapZones _zones = const MapZones();
  String? _selectedDistrictId;
  String? _selectedZoneId;
  String? _activeZoneFocusId;

  // Defaults mostly match Personal Site; metro is opt-in because its three
  // proximity rings are visually dense.
  bool _showCity = true;
  bool _showDistricts = true;
  bool _showMicrodistricts = false;
  bool _showQuartals = false;
  bool _showAreas = true;
  bool _showMetro = false;
  bool _showParks = false;
  bool _showShoppingMalls = false;
  bool _showUniversities = false;

  @override
  void initState() {
    super.initState();
    _zoom = widget.centerZoom;
    _loadZones(focusCity: widget.city.isNotEmpty);
    if (widget.city.isEmpty) _scheduleFitToPoints();
  }

  @override
  void dispose() {
    _cameraAnim.dispose();
    super.dispose();
  }

  LatLng _animStartCenter = const LatLng(0, 0);
  double _animStartZoom = 0;
  LatLng _animDestCenter = const LatLng(0, 0);
  double _animDestZoom = 0;

  void _onCameraAnimTick() {
    if (!mounted) return;
    final t = Curves.easeInOutCubic.transform(_cameraAnim.value);
    try {
      _controller.move(
        LatLng(
          _animStartCenter.latitude +
              (_animDestCenter.latitude - _animStartCenter.latitude) * t,
          _animStartCenter.longitude +
              (_animDestCenter.longitude - _animStartCenter.longitude) * t,
        ),
        _animStartZoom + (_animDestZoom - _animStartZoom) * t,
      );
    } catch (_) {}
  }

  /// Eases the camera to [destCenter]/[destZoom] instead of snapping there —
  /// used for every programmatic move (zone focus, result auto-fit, cluster
  /// expand) so the map reads as one continuous motion rather than a jump cut.
  void _animatedMoveTo(LatLng destCenter, double destZoom) {
    try {
      _animStartCenter = _controller.camera.center;
      _animStartZoom = _controller.camera.zoom;
    } catch (_) {
      // Not attached yet (e.g. called from the very first didUpdateWidget).
      try {
        _controller.move(destCenter, destZoom);
      } catch (_) {}
      return;
    }
    _animDestCenter = destCenter;
    _animDestZoom = destZoom;
    _cameraAnim
      ..stop()
      ..value = 0;
    _cameraAnim.forward();
  }

  void _animatedFitCamera(CameraFit fit) {
    try {
      final target = fit.fit(_controller.camera);
      _animatedMoveTo(target.center, target.zoom);
    } catch (_) {
      // Falls back to an instant fit if the camera isn't attached yet.
      _controller.fitCamera(fit);
    }
  }

  Future<void> _loadZones({bool focusCity = false}) async {
    if (widget.country.isEmpty || widget.city.isEmpty) return;
    final zones = await _api.fetchMapZones(
      widget.country,
      widget.city,
      locale: widget.locale,
    );
    if (!mounted) return;
    setState(() => _zones = zones);

    // Filters and map share one canonical selection. If a saved preset, filter
    // sheet or deep link already selected a zone, restore it immediately and
    // center the map on the same catalog entity.
    if (_syncSelectionFromFilters(focus: !_isFocused)) return;

    // A city typed/selected in filters is an explicit geographic scope, so it
    // wins over automatic result fitting. Use the real city boundary when the
    // catalog has it, otherwise its canonical center + accuracy radius.
    if (focusCity && zones.cityZone != null && !_isFocused) {
      _activeZoneFocusId = zones.cityZone!.id;
      _focusZone(zones.cityZone!, maxZoom: 12);
    }
  }

  @override
  void didUpdateWidget(covariant MapView old) {
    super.didUpdateWidget(old);
    if (old.center != widget.center || old.centerZoom != widget.centerZoom) {
      _animatedMoveTo(widget.center, widget.centerZoom);
    }

    final cityChanged =
        old.country != widget.country || old.city != widget.city;
    final listingsChanged = !identical(old.listings, widget.listings);
    final localeChanged = old.locale != widget.locale;
    if (cityChanged || listingsChanged) {
      _expandedGroupKey = null;
      _expandedGroupPage = 0;
    }
    if (cityChanged) {
      _selectedDistrictId = null;
      _selectedZoneId = null;
      _activeZoneFocusId = null;
      _zones = const MapZones();
      _loadZones(focusCity: widget.city.isNotEmpty);
    } else if (localeChanged) {
      _loadZones();
    }

    if ((cityChanged || listingsChanged) &&
        widget.city.isEmpty &&
        _activeZoneFocusId == null) {
      _scheduleFitToPoints();
    }
  }

  /// Closed ring with a real-world radius in metres. Used only when the geo
  /// catalog has no boundary and for explicit metro walking-distance rings.
  List<LatLng> _circleRingAt(double lat, double lng, double radiusM) {
    const points = 64;
    final latRad = lat * math.pi / 180;
    final dLat = radiusM / 111320;
    final cosLat = math.cos(latRad).abs().clamp(0.01, 1.0).toDouble();
    final dLng = radiusM / (111320 * cosLat);
    return [
      for (var i = 0; i <= points; i++)
        LatLng(
          lat + dLat * math.sin(2 * math.pi * i / points),
          lng + dLng * math.cos(2 * math.pi * i / points),
        ),
    ];
  }

  List<LatLng> _circleRing(DistrictZone zone, [double? radiusM]) =>
      _circleRingAt(zone.lat, zone.lng, radiusM ?? zone.radiusM);

  List<List<LatLng>> _ringsFor(DistrictZone zone) =>
      zone.boundaryRings.isNotEmpty ? zone.boundaryRings : [_circleRing(zone)];

  double _maxZoomForZone(String type) {
    switch (type) {
      case 'city':
        return 12;
      case 'district':
        return 13.5;
      case 'microdistrict':
        return 15;
      case 'mahalla':
      case 'local_area':
      case 'development_area':
      case 'metro':
      case 'poi.park':
      case 'poi.shopping_mall':
      case 'poi.university':
        return 16;
      default:
        return 15;
    }
  }

  void _focusZone(DistrictZone zone, {double? maxZoom}) {
    final points = <LatLng>[for (final ring in _ringsFor(zone)) ...ring];
    final fallbackZoom =
        math.min(maxZoom ?? _maxZoomForZone(zone.type), 19.0).toDouble();
    try {
      if (points.length >= 2) {
        _animatedFitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: const EdgeInsets.all(34),
            maxZoom: maxZoom ?? _maxZoomForZone(zone.type),
          ),
        );
      } else {
        _animatedMoveTo(LatLng(zone.lat, zone.lng), fallbackZoom);
      }
    } catch (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _controller.move(LatLng(zone.lat, zone.lng), fallbackZoom);
        } catch (_) {}
      });
    }
  }

  DistrictZone? _ancestorOfType(DistrictZone zone, String type) {
    var current = zone;
    for (var depth = 0; depth < 8; depth++) {
      if (current.type == type) return current;
      final parent = _zones.byId(current.parentId);
      if (parent == null) return null;
      current = parent;
    }
    return null;
  }

  /// The zones behind the currently chosen station names. Recomputed from
  /// the live filter set on every build rather than cached, since the list is
  /// short (a handful of stations at most) and the alternative is another
  /// piece of state to keep in sync with AppState.
  List<DistrictZone> _selectedMetroStations(Filters filters) {
    if (filters.metro.isEmpty) return const [];
    return [
      for (final station in _zones.metroStations)
        if (filters.metro.contains(station.name)) station,
    ];
  }

  DistrictZone? _zoneByName(Iterable<DistrictZone> zones, String name) {
    if (name.isEmpty) return null;
    for (final zone in zones) {
      if (zone.name == name) return zone;
    }
    return null;
  }

  DistrictZone? _zoneMatchingFilters() {
    final filters = context.read<AppState>().filters;
    // Metro is multi-select; its first station stands in for "the selected
    // zone" wherever this file's existing single-zone bookkeeping
    // (_selectedZoneId, focus-on-change, the label chip) needs one value.
    // The real membership test for drawing/highlighting is always
    // filters.metro.contains(...), not this.
    if (filters.metro.isNotEmpty) {
      final primary = _zoneByName(_zones.metroStations, filters.metro.first);
      if (primary != null) return primary;
    }
    return _zoneByName(_zones.areaZones, filters.area) ??
        _zoneByName(_zones.quartalMarkers, filters.quartal) ??
        _zoneByName(_zones.microdistrictMarkers, filters.microdistrict) ??
        _zoneByName(_zones.districtZones, filters.district);
  }

  void _showLayerFor(DistrictZone zone) {
    switch (zone.type) {
      case 'district':
        _showDistricts = true;
      case 'microdistrict':
        _showMicrodistricts = true;
      case 'mahalla':
        _showQuartals = true;
      case 'local_area':
      case 'development_area':
        _showAreas = true;
      case 'metro':
        _showMetro = true;
      case 'poi.park':
        _showParks = true;
      case 'poi.shopping_mall':
        _showShoppingMalls = true;
      case 'poi.university':
        _showUniversities = true;
    }
  }

  bool _syncSelectionFromFilters({bool focus = false}) {
    if (!mounted) return false;
    final zone = _zoneMatchingFilters();
    if (zone == null) {
      if (_selectedZoneId != null || _selectedDistrictId != null) {
        setState(() {
          _selectedZoneId = null;
          _selectedDistrictId = null;
          _activeZoneFocusId = null;
        });
      }
      return false;
    }

    final district = _ancestorOfType(zone, 'district');
    final changed = _selectedZoneId != zone.id;
    if (changed) {
      setState(() {
        _selectedZoneId = zone.id;
        _selectedDistrictId = district?.id;
        _activeZoneFocusId = zone.id;
        _expandedGroupKey = null;
        _showLayerFor(zone);
      });
    } else {
      _showLayerFor(zone);
    }
    if (focus) _focusZone(zone);
    return true;
  }

  // metroRadiusM is now unused here: metro selection bypasses this method
  // entirely (see _toggleMetroStation) since it is multi-select and shares
  // one radius/arc across every chosen station rather than "select zone,
  // apply its own radius".
  Future<void> _applyZoneScope(DistrictZone zone) async {
    final state = context.read<AppState>();
    final current = state.filters;
    // A map geography pick becomes the new search scope. Text search is a
    // competing free-form scope, so clear it before applying the canonical
    // geographic filter. AppState notifies the compact filters immediately,
    // and their controller sync clears the visible search input as well.
    final scoped = current.copyWith(query: '');
    final district = _ancestorOfType(zone, 'district');
    final microdistrict = _ancestorOfType(zone, 'microdistrict');
    final mahalla = _ancestorOfType(zone, 'mahalla');

    final next = switch (zone.type) {
      'district' => scoped.copyWith(
          district: zone.name,
          microdistrict: '',
          quartal: '',
          area: '',
        ),
      'microdistrict' => scoped.copyWith(
          district: district?.name ?? current.district,
          microdistrict: zone.name,
          quartal: '',
          area: '',
        ),
      'mahalla' => scoped.copyWith(
          district: district?.name ?? current.district,
          microdistrict: microdistrict?.name ?? current.microdistrict,
          quartal: zone.name,
          area: '',
        ),
      'local_area' => scoped.copyWith(
          district: district?.name ?? current.district,
          microdistrict: microdistrict?.name ?? current.microdistrict,
          quartal: mahalla?.name ?? current.quartal,
          area: zone.name,
        ),
      'development_area' => scoped.copyWith(
          district: district?.name ?? current.district,
          microdistrict: microdistrict?.name ?? current.microdistrict,
          quartal: mahalla?.name ?? current.quartal,
          area: zone.name,
        ),
      _ => current,
    };

    if (identical(next, current)) return;
    state.updateFilters(next);
    await state.search();
    if (!mounted) return;
    await state.loadMapListings();
  }

  Future<void> _clearZoneScope(DistrictZone zone) async {
    final state = context.read<AppState>();
    final current = state.filters;
    final next = switch (zone.type) {
      'district' => current.copyWith(
          district: '',
          microdistrict: '',
          quartal: '',
          area: '',
        ),
      'microdistrict' => current.copyWith(
          microdistrict: '',
          quartal: '',
          area: '',
        ),
      'mahalla' => current.copyWith(quartal: '', area: ''),
      'local_area' || 'development_area' => current.copyWith(area: ''),
      _ => current,
    };
    state.updateFilters(next);
    await state.search();
    if (!mounted) return;
    await state.loadMapListings();
  }

  // Metro no longer reaches this method at all -- it is multi-select with
  // its own toggle-on-tap interaction (_toggleMetroStation), not the
  // single-zone select/confirm/clear cycle every other geography kind here
  // still uses.
  Future<void> _selectZone(DistrictZone zone) async {
    final sameZone = _selectedZoneId == zone.id;

    if (sameZone) {
      setState(() {
        _selectedZoneId = null;
        _selectedDistrictId = null;
        _activeZoneFocusId = null;
        _expandedGroupKey = null;
      });
      await _clearZoneScope(zone);
      return;
    }

    final district = _ancestorOfType(zone, 'district');
    setState(() {
      _selectedZoneId = zone.id;
      _selectedDistrictId = district?.id;
      _activeZoneFocusId = zone.id;
      _expandedGroupKey = null;
      _showLayerFor(zone);
    });
    _focusZone(zone);
    await _applyZoneScope(zone);
  }

  double _ringAreaScore(List<LatLng> ring) {
    if (ring.isEmpty) return double.infinity;
    var minLat = ring.first.latitude;
    var maxLat = minLat;
    var minLng = ring.first.longitude;
    var maxLng = minLng;
    for (final point in ring.skip(1)) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }
    return (maxLat - minLat).abs() * (maxLng - minLng).abs();
  }

  DistrictZone? _hitZone(LatLng point, Iterable<DistrictZone> zones) {
    DistrictZone? best;
    var bestArea = double.infinity;
    for (final zone in zones) {
      for (final ring in _ringsFor(zone)) {
        if (!_pointInPolygon(point, ring)) continue;
        final area = _ringAreaScore(ring);
        if (area < bestArea) {
          best = zone;
          bestArea = area;
        }
        break;
      }
    }
    return best;
  }

  /// Listings restricted to the drawn area (once it has at least 3 points).
  List<MapListingPoint> get _visible {
    final located = widget.listings;
    if (_area.length < 3) return located;
    return located
        .where((l) => _pointInPolygon(LatLng(l.lat, l.lng), _area))
        .toList();
  }

  // Ray-casting point-in-polygon test on lat/lng.
  bool _pointInPolygon(LatLng p, List<LatLng> poly) {
    bool inside = false;
    for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final xi = poly[i].longitude, yi = poly[i].latitude;
      final xj = poly[j].longitude, yj = poly[j].latitude;
      final intersect = ((yi > p.latitude) != (yj > p.latitude)) &&
          (p.longitude < (xj - xi) * (p.latitude - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  bool get _isFocused => widget.centerZoom >= 17.5;

  String _listingKey(MapListingPoint listing) => listing.key;

  void _scheduleFitToPoints() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitToPoints();
    });
  }

  /// Matches Personal Site's fitToPoints(): frame the complete compact map
  /// feed once and cap the initial zoom at 14. Explicit city/zone scopes take
  /// priority and suppress this auto-fit.
  void _fitToPoints() {
    if (_isFocused || widget.city.isNotEmpty || _activeZoneFocusId != null) {
      return;
    }
    final located = widget.listings;
    if (located.isEmpty) return;
    final keys = located.map(_listingKey).toList()..sort();
    final signature = keys.join(',');
    if (signature == _lastFitSignature) return;
    try {
      // The very first fit (no prior signature) should land immediately —
      // animating from the default world view reads as a needless swoop.
      final isInitialFit = _lastFitSignature.isEmpty;
      final bounds = CameraFit.bounds(
        bounds: LatLngBounds.fromPoints([
          for (final listing in located) LatLng(listing.lat, listing.lng),
        ]),
        padding: const EdgeInsets.all(30),
        maxZoom: 14,
      );
      if (isInitialFit) {
        _controller.fitCamera(bounds);
      } else {
        _animatedFitCamera(bounds);
      }
      _lastFitSignature = signature;
    } catch (_) {
      // The controller can still be attaching on the very first frame.
    }
  }

  double _worldWidth([double? zoom]) {
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
  List<_PinGroup> _groupsFor(List<MapListingPoint> located, {double? zoom}) {
    if (located.isEmpty) return const [];
    final z = zoom ?? _zoom;
    final bucketedZoom = (z * 8).round() / 8;
    final key = '$bucketedZoom|${located.length}|${identityHashCode(located)}';
    final cached = _groupsCache;
    if (cached != null && _groupsCacheKey == key) return cached;
    final groups = _computeGroups(located, bucketedZoom);
    _groupsCache = groups;
    _groupsCacheKey = key;
    return groups;
  }

  List<_PinGroup> _computeGroups(List<MapListingPoint> located, double zoom) {
    final clusters = greedyScreenSpaceClusters<MapListingPoint>(
      located,
      project: (listing) {
        final point = _worldPixel(LatLng(listing.lat, listing.lng), zoom);
        return ScreenCoordinate(point.dx, point.dy);
      },
      latitudeOf: (listing) => listing.lat,
      longitudeOf: (listing) => listing.lng,
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
  int _expandedGroupPage = 0;

  /// Price pills use the same conservative collision rule as before, but the
  /// complete set is computed once per map build through nearby spatial cells
  /// rather than scanning every group for every singleton marker.
  Set<String> _standalonePriceGroupKeys(List<_PinGroup> groups) {
    if (groups.isEmpty) return const {};
    final ownRadius = math.sqrt(
      math.pow(_priceMarkerWidth / 2, 2) + math.pow(_priceMarkerHeight / 2, 2),
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

  void _openGroup(_PinGroup group) {
    if (group.listings.length == 1) {
      widget.onTapListing(group.listings.first);
      return;
    }
    _animatedMoveTo(group.point, _zoom);
    setState(() {
      _expandedGroupKey = group.key;
      _expandedGroupPage = 0;
    });
  }

  List<Marker> _markersForGroup(_PinGroup group, bool showStandalonePrice) {
    if (group.listings.length == 1 && showStandalonePrice) {
      final listing = group.listings.first;
      return [
        Marker(
          point: group.point,
          width: _priceMarkerWidth,
          height: _priceMarkerHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _handlePointTap(
              group.point,
              () => widget.onTapListing(listing),
            ),
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
          key: Key('map-listing-group-${group.key}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _handlePointTap(group.point, () => _openGroup(group)),
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
    final page = paginateMapGroup(
      group.listings,
      pageIndex: _expandedGroupPage,
      pageSize: _radialCapacity,
    );
    return Marker(
      point: group.point,
      width: 280,
      height: 280,
      alignment: Alignment.center,
      child: _RadialClusterMarker(
        items: page.items,
        pageIndex: page.pageIndex,
        pageCount: page.pageCount,
        rates: widget.rates,
        displayCurrency: widget.displayCurrency,
        onTapListing: widget.onTapListing,
        onPreviousPage: page.hasPrevious
            ? () => setState(() => _expandedGroupPage = page.pageIndex - 1)
            : null,
        onNextPage: page.hasNext
            ? () => setState(() => _expandedGroupPage = page.pageIndex + 1)
            : null,
        onClose: () => setState(() {
          _expandedGroupKey = null;
          _expandedGroupPage = 0;
        }),
      ),
    );
  }

  double _distanceM(LatLng a, LatLng b) {
    const earthRadiusM = 6371000.0;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * earthRadiusM * math.asin(math.sqrt(h));
  }

  (DistrictZone, num)? _metroHit(LatLng point) {
    DistrictZone? nearest;
    var nearestM = double.infinity;
    for (final station in _zones.metroStations) {
      final distance = _distanceM(point, LatLng(station.lat, station.lng));
      if (distance < nearestM) {
        nearest = station;
        nearestM = distance;
      }
    }
    if (nearest == null || nearestM > 1000) return null;
    final radius = nearestM <= 200
        ? 200
        : nearestM <= 500
            ? 500
            : 1000;
    return (nearest, radius);
  }

  /// Adds or removes one station from the multi-select set. The first
  /// station chosen (starting from no selection) adopts the tapped preset
  /// ring as its radius, matching _metroHit's 200/500/1000m proximity read;
  /// every station after that shares whatever radius/arc is already set,
  /// because the shape describes one rule ("within 780m, west side"), not a
  /// separate one per station.
  Future<void> _toggleMetroStation(
    DistrictZone station, {
    num? presetRadiusM,
  }) async {
    final state = context.read<AppState>();
    final current = state.filters;
    final wasEmpty = current.metro.isEmpty;
    final adding = !current.metro.contains(station.name);
    final next = adding
        ? ({...current.metro, station.name})
        : (current.metro.toSet()..remove(station.name));

    var updated = current.copyWith(metro: next, query: '');
    if (next.isEmpty) {
      updated = updated.copyWith(
        clearMetroMaxM: true,
        clearMetroBearing: true,
      );
    } else if (wasEmpty && adding) {
      updated = updated.copyWith(
        metroMaxM: presetRadiusM ?? defaultMetroRadiusM,
      );
    }

    state.updateFilters(updated);
    // _selectedZoneId/_activeZoneFocusId are not touched here: they are
    // driven reactively off filters.metro by _zoneMatchingFilters, the same
    // path every other geography kind in this file already uses.
    await state.search();
    if (!mounted) return;
    await state.loadMapListings();
  }

  /// Converts a raw touch position (screen/global coordinates) into the
  /// LatLng under it. Marker has no native drag support in flutter_map, so
  /// this is the same technique the package's own "Draggable Marker" example
  /// uses: find this widget's RenderBox via _mapAreaKey, make the point
  /// local to it, then let the map's own camera invert its projection --
  /// correct at any zoom or rotation without hand-rolling Mercator math.
  LatLng? _globalToLatLng(Offset global) {
    final renderBox =
        _mapAreaKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) return null;
    final local = renderBox.globalToLocal(global);
    return MapCamera.of(context).pointToLatLng(
      math.Point(local.dx, local.dy),
    );
  }

  num _shapeRadiusM(Filters filters) =>
      _draftMetroRadiusM ?? filters.metroMaxM ?? defaultMetroRadiusM;
  num? _shapeBearingFrom(Filters filters) =>
      _draftMetroBearingFrom ?? filters.metroBearingFrom;
  num? _shapeBearingTo(Filters filters) =>
      _draftMetroBearingTo ?? filters.metroBearingTo;

  /// Where each handle sits: the radius grip on the arc's midpoint, the
  /// wedge grips on its edges.
  double _handleBearing(Filters filters, String kind) {
    final from = _shapeBearingFrom(filters)?.toDouble();
    final to = _shapeBearingTo(filters)?.toDouble();
    if (from == null || to == null) {
      return kind == 'from' ? 270 : (kind == 'to' ? 90 : 0);
    }
    if (kind == 'from') return from;
    if (kind == 'to') return to;
    return normalizeBearing(from + normalizeBearing(to - from) / 2);
  }

  void _onMetroHandlePanUpdate(
    String kind,
    LatLng anchor,
    Filters filters,
    DragUpdateDetails details,
  ) {
    final target = _globalToLatLng(details.globalPosition);
    if (target == null) return;
    setState(() {
      if (kind == 'radius') {
        // Snapped to 10m: the filter itself is exact, but a radius that
        // reads "783 m" after a drag is noise dressed up as precision.
        final metres = metresBetween(anchor, target);
        final snapped = (metres / 10).round() * 10;
        _draftMetroRadiusM = snapped
            .clamp(metroMinRadiusM.round(), metroMaxRadiusM.round())
            .toDouble();
      } else {
        // Opening the arc from a full circle anchors the opposite edge 180
        // degrees away, so the first drag yields a half-plane rather than a
        // zero-width sliver that would match nothing.
        final bearing =
            normalizeBearing(bearingBetween(anchor, target).roundToDouble());
        final from = _shapeBearingFrom(filters)?.toDouble();
        final to = _shapeBearingTo(filters)?.toDouble();
        if (kind == 'from') {
          _draftMetroBearingFrom = bearing;
          _draftMetroBearingTo = to ?? normalizeBearing(bearing + 180);
        } else {
          _draftMetroBearingTo = bearing;
          _draftMetroBearingFrom = from ?? normalizeBearing(bearing - 180);
        }
      }
    });
  }

  Future<void> _onMetroHandlePanEnd() async {
    final state = context.read<AppState>();
    final filters = state.filters;
    final radius =
        _draftMetroRadiusM ?? filters.metroMaxM ?? defaultMetroRadiusM;
    final from = _draftMetroBearingFrom ?? filters.metroBearingFrom;
    final to = _draftMetroBearingTo ?? filters.metroBearingTo;
    final hasArc = from != null && to != null;

    setState(() {
      _draggingMetroHandle = null;
      _draftMetroRadiusM = null;
      _draftMetroBearingFrom = null;
      _draftMetroBearingTo = null;
    });

    // One request per drag, on release: the shape redraws locally at pointer
    // speed via the draft fields above, but only the settled value is worth
    // asking the server (or the client-side proximity filter) about.
    state.updateFilters(
      filters.copyWith(
        metroMaxM: radius,
        metroBearingFrom: hasArc ? from : null,
        metroBearingTo: hasArc ? to : null,
        clearMetroBearing: !hasArc,
      ),
    );
    await state.search();
    if (!mounted) return;
    await state.loadMapListings();
  }

  void _handlePointTap(LatLng point, VoidCallback action) {
    if (_drawing) {
      setState(() => _area.add(point));
      return;
    }
    action();
  }

  void _onMapTap(LatLng point) {
    if (_expandedGroupKey != null) {
      setState(() {
        _expandedGroupKey = null;
        _expandedGroupPage = 0;
      });
    }
    if (_drawing) {
      setState(() => _area.add(point));
      return;
    }

    if (_showMetro) {
      final metroHit = _metroHit(point);
      if (metroHit != null) {
        unawaited(_toggleMetroStation(metroHit.$1, presetRadiusM: metroHit.$2));
        return;
      }
    }

    // Hit-test narrow geographic scopes before broad districts. This prevents
    // a district polygon from intercepting taps intended for a mahalla,
    // microdistrict or local area inside it.
    final candidates = <DistrictZone?>[
      if (_showParks || _showShoppingMalls || _showUniversities)
        _hitZone(point, <DistrictZone>[
          if (_showParks) ..._zones.parks,
          if (_showShoppingMalls) ..._zones.shoppingMalls,
          if (_showUniversities) ..._zones.universities,
        ]),
      if (_showAreas) _hitZone(point, _zones.areaZones),
      if (_showQuartals) _hitZone(point, _zones.quartalMarkers),
      if (_showMicrodistricts) _hitZone(point, _zones.microdistrictMarkers),
      if (_showDistricts) _hitZone(point, _zones.districtZones),
    ];
    for (final zone in candidates) {
      if (zone == null) continue;
      unawaited(_selectZone(zone));
      return;
    }
  }

  void _clearArea() => setState(() => _area.clear());

  Polygon _zonePolygon(
    DistrictZone zone,
    List<LatLng> ring, {
    required double fillAlpha,
    double borderWidth = 2,
  }) {
    final selected = zone.id == _selectedZoneId;
    final districtDimmed = _selectedDistrictId != null &&
        zone.type == 'district' &&
        zone.id != _selectedDistrictId;
    final base = _parseHexColor(zone.colorHex);
    final color = districtDimmed ? _desaturate(base, 0.85) : base;
    return Polygon(
      points: ring,
      borderStrokeWidth: selected ? borderWidth + 1 : borderWidth,
      borderColor: color.withValues(
        alpha: selected ? 1 : (districtDimmed ? 0.5 : 0.72),
      ),
      color: color.withValues(
        alpha: selected ? math.min(fillAlpha + 0.13, 0.42) : fillAlpha,
      ),
    );
  }

  Polygon _proximityRing(
    DistrictZone place,
    double radiusM,
    Color color, {
    bool selected = false,
  }) {
    return Polygon(
      points: _circleRing(place, radiusM),
      borderStrokeWidth: selected ? 3 : 1.5,
      borderColor: color.withValues(alpha: selected ? 1 : 0.78),
      color: color.withValues(alpha: selected ? 0.18 : 0.075),
    );
  }

  List<Marker> _poiMarkers(List<DistrictZone> pois, IconData icon) => [
        for (final poi in pois)
          Marker(
            point: LatLng(poi.lat, poi.lng),
            width: 34,
            height: 34,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _handlePointTap(
                LatLng(poi.lat, poi.lng),
                () => unawaited(_selectZone(poi)),
              ),
              child: _PoiMarker(
                icon: icon,
                color: _parseHexColor(poi.colorHex),
                selected: poi.id == _selectedZoneId,
              ),
            ),
          ),
      ];

  /// The three grips on the chosen wedge: one for distance (on the arc,
  /// snapping to 10m), two for the arc edges. Anchored at the first chosen
  /// station -- several stations share one shape, so three grips per station
  /// would be a thicket, and moving one would have to move the rest anyway.
  List<Marker> _metroHandleMarkers(Filters filters) {
    final stations = _selectedMetroStations(filters);
    if (stations.isEmpty) return const [];
    final anchor = LatLng(stations.first.lat, stations.first.lng);
    final radius = _shapeRadiusM(filters).toDouble();

    Marker handle(String kind) {
      final bearing = _handleBearing(filters, kind);
      final point = destinationPoint(anchor, bearing, radius);
      return Marker(
        point: point,
        width: 40,
        height: 40,
        // Larger than the visual dot: this is the actual drag/tap target,
        // sized for a fingertip rather than the ~14px the dot itself needs.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => setState(() => _draggingMetroHandle = kind),
          onPanUpdate: (details) =>
              _onMetroHandlePanUpdate(kind, anchor, filters, details),
          onPanEnd: (_) => unawaited(_onMetroHandlePanEnd()),
          child: _MetroHandleMarker(
            kind: kind,
            active: _draggingMetroHandle == kind,
          ),
        ),
      );
    }

    return [handle('radius'), handle('from'), handle('to')];
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsState>().s;
    final appState = context.watch<AppState>();
    final desiredZone = _zoneMatchingFilters();
    if (desiredZone?.id != _selectedZoneId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncSelectionFromFilters(focus: !_isFocused);
      });
    }
    final visible = _visible;
    final groups = _groupsFor(visible);
    final standalonePriceGroupKeys = _standalonePriceGroupKeys(groups);
    final expandedGroup = _expandedGroup(groups);
    final selectedZone = _zones.byId(_selectedZoneId);
    return Stack(
      children: [
        KeyedSubtree(
            key: _mapAreaKey,
            child: FlutterMap(
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
                      _expandedGroupPage = 0;
                    });
                  }
                },
              ),
              children: [
                if (widget.showBaseTiles)
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.flat_finder',
                    maxZoom: 19,
                    // Keep a ring of off-screen tiles cached and fade new tiles
                    // in instead of popping them in, so panning/zooming doesn't
                    // flash blank tiles while the network catches up.
                    keepBuffer: 3,
                    panBuffer: 2,
                    tileDisplay: const TileDisplay.fadeIn(
                      duration: Duration(milliseconds: 150),
                    ),
                  ),
                if (_showCity &&
                    _zones.cityZone?.boundaryRings.isNotEmpty == true)
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
                if (_showDistricts && _zones.districtZones.isNotEmpty)
                  PolygonLayer(
                    polygons: [
                      for (final zone in _zones.districtZones)
                        for (final ring in _ringsFor(zone))
                          _zonePolygon(
                            zone,
                            ring,
                            fillAlpha: 0.20,
                            borderWidth: 2.5,
                          ),
                    ],
                  ),
                if (_showAreas && _zones.areaZones.isNotEmpty)
                  PolygonLayer(
                    polygons: [
                      for (final zone in _zones.areaZones)
                        for (final ring in _ringsFor(zone))
                          _zonePolygon(zone, ring, fillAlpha: 0.14),
                    ],
                  ),
                if (_showMicrodistricts &&
                    _zones.microdistrictMarkers.isNotEmpty)
                  PolygonLayer(
                    polygons: [
                      for (final zone in _zones.microdistrictMarkers)
                        for (final ring in _ringsFor(zone))
                          _zonePolygon(zone, ring, fillAlpha: 0.12),
                    ],
                  ),
                if (_showQuartals && _zones.quartalMarkers.isNotEmpty)
                  PolygonLayer(
                    polygons: [
                      for (final zone in _zones.quartalMarkers)
                        for (final ring in _ringsFor(zone))
                          _zonePolygon(zone, ring, fillAlpha: 0.15),
                    ],
                  ),
                // Presets while nothing is picked yet (discovery mode); once any
                // station is chosen its wedge replaces them -- the three
                // overlapping rings across every station were what made a chosen
                // selection hard to read, and are no longer the question being
                // asked.
                if (_showMetro &&
                    _zones.metroStations.isNotEmpty &&
                    appState.filters.metro.isEmpty)
                  PolygonLayer(
                    polygons: [
                      // Largest first so the stronger inner zones stay visible.
                      for (final station in _zones.metroStations)
                        _proximityRing(station, 1000, _metro1000Color),
                      for (final station in _zones.metroStations)
                        _proximityRing(station, 500, _metro500Color),
                      for (final station in _zones.metroStations)
                        _proximityRing(station, 200, _metro200Color),
                    ],
                  ),
                if (_showMetro &&
                    _selectedMetroStations(appState.filters).isNotEmpty)
                  PolygonLayer(
                    polygons: [
                      for (final station
                          in _selectedMetroStations(appState.filters))
                        Polygon(
                          points: sectorPolygon(
                            LatLng(station.lat, station.lng),
                            _shapeRadiusM(appState.filters).toDouble(),
                            from:
                                _shapeBearingFrom(appState.filters)?.toDouble(),
                            to: _shapeBearingTo(appState.filters)?.toDouble(),
                          ),
                          borderStrokeWidth: 2,
                          borderColor:
                              _metroSelectedColor.withValues(alpha: 0.95),
                          color: _metroSelectedColor.withValues(alpha: 0.14),
                        ),
                    ],
                  ),
                if (_showParks && _zones.parks.isNotEmpty)
                  PolygonLayer(
                    polygons: [
                      for (final poi in _zones.parks)
                        _proximityRing(poi, 1000, _metro1000Color),
                      for (final poi in _zones.parks)
                        _proximityRing(poi, 500, _metro500Color),
                      for (final poi in _zones.parks)
                        _proximityRing(poi, 200, _metro200Color),
                      for (final poi in _zones.parks)
                        for (final ring in poi.boundaryRings)
                          _zonePolygon(poi, ring, fillAlpha: 0.12),
                    ],
                  ),
                if (_showShoppingMalls && _zones.shoppingMalls.isNotEmpty)
                  PolygonLayer(
                    polygons: [
                      for (final poi in _zones.shoppingMalls)
                        _proximityRing(poi, 1000, _metro1000Color),
                      for (final poi in _zones.shoppingMalls)
                        _proximityRing(poi, 500, _metro500Color),
                      for (final poi in _zones.shoppingMalls)
                        _proximityRing(poi, 200, _metro200Color),
                      for (final poi in _zones.shoppingMalls)
                        for (final ring in poi.boundaryRings)
                          _zonePolygon(poi, ring, fillAlpha: 0.10),
                    ],
                  ),
                if (_showUniversities && _zones.universities.isNotEmpty)
                  PolygonLayer(
                    polygons: [
                      for (final poi in _zones.universities)
                        _proximityRing(poi, 1000, _metro1000Color),
                      for (final poi in _zones.universities)
                        _proximityRing(poi, 500, _metro500Color),
                      for (final poi in _zones.universities)
                        _proximityRing(poi, 200, _metro200Color),
                      for (final poi in _zones.universities)
                        for (final ring in poi.boundaryRings)
                          _zonePolygon(poi, ring, fillAlpha: 0.10),
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
                                    color: (_selectedDistrictId != null &&
                                            zone.id != _selectedDistrictId)
                                        ? _desaturate(
                                            _parseHexColor(zone.colorHex),
                                            0.85,
                                          ).withValues(alpha: 0.55)
                                        : _parseHexColor(zone.colorHex),
                                  ),
                                ),
                                child: Text(
                                  zone.label,
                                  style: TextStyle(
                                    color: Colors.white.withValues(
                                      alpha: (_selectedDistrictId != null &&
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
                // Once anything is chosen, only chosen stations stay on screen --
                // same "no longer the question being asked" rule as the rings
                // above, applied to the dots themselves.
                if (_showMetro && _zones.metroStations.isNotEmpty)
                  MarkerLayer(
                    markers: [
                      for (final station in appState.filters.metro.isEmpty
                          ? _zones.metroStations
                          : _selectedMetroStations(appState.filters))
                        Marker(
                          point: LatLng(station.lat, station.lng),
                          width: 34,
                          height: 34,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _handlePointTap(
                              LatLng(station.lat, station.lng),
                              () => unawaited(_toggleMetroStation(station)),
                            ),
                            child: _MetroStationMarker(
                              selected:
                                  appState.filters.metro.contains(station.name),
                            ),
                          ),
                        ),
                    ],
                  ),
                if (_showMetro &&
                    _selectedMetroStations(appState.filters).isNotEmpty)
                  MarkerLayer(
                    markers: _metroHandleMarkers(appState.filters),
                  ),
                if (_showParks && _zones.parks.isNotEmpty)
                  MarkerLayer(
                    markers: _poiMarkers(_zones.parks, Icons.park_outlined),
                  ),
                if (_showShoppingMalls && _zones.shoppingMalls.isNotEmpty)
                  MarkerLayer(
                    markers: _poiMarkers(
                      _zones.shoppingMalls,
                      Icons.local_mall_outlined,
                    ),
                  ),
                if (_showUniversities && _zones.universities.isNotEmpty)
                  MarkerLayer(
                    markers: _poiMarkers(
                      _zones.universities,
                      Icons.school_outlined,
                    ),
                  ),
                if (selectedZone != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(selectedZone.lat, selectedZone.lng),
                        width: 160,
                        height: 26,
                        child: IgnorePointer(
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.72),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: selectedZone.type == 'metro'
                                      ? _metro200Color
                                      : _parseHexColor(selectedZone.colorHex),
                                ),
                              ),
                              child: Text(
                                selectedZone.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
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
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.15),
                      ),
                    ],
                  ),
                if (widget.radiusCenter != null && widget.radiusM != null)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: _circleRingAt(
                          widget.radiusCenter!.latitude,
                          widget.radiusCenter!.longitude,
                          widget.radiusM!,
                        ),
                        borderStrokeWidth: 2.5,
                        borderColor: const Color(0xFF2563EB),
                        color: const Color(0xFF2563EB).withValues(alpha: 0.14),
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
                    if (widget.radiusCenter != null)
                      Marker(
                        point: widget.radiusCenter!,
                        width: 46,
                        height: 46,
                        child: const Icon(
                          Icons.work,
                          color: Color(0xFF2563EB),
                          size: 36,
                        ),
                      ),
                    for (final group in groups)
                      if (expandedGroup == null ||
                          group.key != expandedGroup.key)
                        ..._markersForGroup(
                          group,
                          standalonePriceGroupKeys.contains(group.key),
                        ),
                    if (expandedGroup != null)
                      _radialMarkerForGroup(expandedGroup),
                    if (_isFocused && expandedGroup == null)
                      Marker(
                        point: widget.center,
                        width: 54,
                        height: 54,
                        child: const IgnorePointer(child: _FocusMarker()),
                      ),
                  ],
                ),
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('© OpenStreetMap contributors'),
                  ],
                ),
              ],
            )),
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
              if (widget.onRadiusCenterChanged != null) ...[
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'radiusCenter',
                  tooltip: 'Указать работу на карте',
                  onPressed: () => setState(
                    () => _placingRadiusCenter = !_placingRadiusCenter,
                  ),
                  backgroundColor: _placingRadiusCenter
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.surface,
                  foregroundColor: _placingRadiusCenter
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSurface,
                  child: const Icon(Icons.work_outline),
                ),
              ],
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
        if (widget.radiusCenter != null &&
            widget.radiusM != null &&
            widget.onRadiusChanged != null)
          Positioned(
            left: 12,
            right: 76,
            bottom: 18,
            child: Card(
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  const Icon(Icons.work_outline, size: 20),
                  Expanded(
                    child: Slider(
                      min: 500,
                      max: 30000,
                      divisions: 59,
                      value: widget.radiusM!.clamp(500, 30000),
                      onChanged: widget.onRadiusChanged,
                    ),
                  ),
                  Text('${(widget.radiusM! / 1000).toStringAsFixed(1)} км'),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        if (_zones.cityZone?.boundaryRings.isNotEmpty == true ||
            _zones.districtZones.isNotEmpty ||
            _zones.microdistrictMarkers.isNotEmpty ||
            _zones.quartalMarkers.isNotEmpty ||
            _zones.areaZones.isNotEmpty ||
            _zones.metroStations.isNotEmpty ||
            _zones.parks.isNotEmpty ||
            _zones.shoppingMalls.isNotEmpty ||
            _zones.universities.isNotEmpty)
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
                  if (_zones.metroStations.isNotEmpty)
                    _ZoneToggle(
                      label: s.t('metro'),
                      active: _showMetro,
                      onTap: () => setState(() => _showMetro = !_showMetro),
                    ),
                  if (_zones.parks.isNotEmpty)
                    _ZoneToggle(
                      label: s.t('parks'),
                      active: _showParks,
                      onTap: () => setState(() => _showParks = !_showParks),
                    ),
                  if (_zones.shoppingMalls.isNotEmpty)
                    _ZoneToggle(
                      label: s.t('shoppingMalls'),
                      active: _showShoppingMalls,
                      onTap: () => setState(
                        () => _showShoppingMalls = !_showShoppingMalls,
                      ),
                    ),
                  if (_zones.universities.isNotEmpty)
                    _ZoneToggle(
                      label: s.t('universities'),
                      active: _showUniversities,
                      onTap: () => setState(
                        () => _showUniversities = !_showUniversities,
                      ),
                    ),
                ],
              ),
            ),
          ),
        if ((_showMetro && _zones.metroStations.isNotEmpty) ||
            (_showParks && _zones.parks.isNotEmpty) ||
            (_showShoppingMalls && _zones.shoppingMalls.isNotEmpty) ||
            (_showUniversities && _zones.universities.isNotEmpty))
          Positioned(left: 12, bottom: 12, child: const _MetroLegend()),
      ],
    );
  }
}

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
            color:
                active ? scheme.primary : Colors.black.withValues(alpha: 0.55),
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

class _MetroLegend extends StatelessWidget {
  const _MetroLegend();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LegendItem(color: _metro200Color, label: '200 м'),
          SizedBox(width: 8),
          _LegendItem(color: _metro500Color, label: '500 м'),
          SizedBox(width: 8),
          _LegendItem(color: _metro1000Color, label: '1 км'),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _MetroStationMarker extends StatelessWidget {
  const _MetroStationMarker({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected
            ? Theme.of(context).colorScheme.primary
            : Colors.black.withValues(alpha: 0.78),
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? Colors.white : _metro200Color,
          width: selected ? 2.5 : 2,
        ),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3)],
      ),
      child: const Icon(Icons.subway_outlined, size: 18, color: Colors.white),
    );
  }
}

/// The distance grip is round, the two arc grips are diamonds, so which one
/// is under a finger is obvious without reading a tooltip -- Flutter has no
/// map-native tooltip-on-hover equivalent to lean on here the way the web
/// build does.
class _MetroHandleMarker extends StatelessWidget {
  const _MetroHandleMarker({required this.kind, this.active = false});
  final String kind; // 'radius' | 'from' | 'to'
  final bool active; // true while this exact handle is being dragged

  @override
  Widget build(BuildContext context) {
    final isArc = kind != 'radius';
    final size = active ? 18.0 : 14.0;
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: isArc ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: isArc ? BorderRadius.circular(3) : null,
        border: Border.all(
          color: isArc ? const Color(0xFF8B5CF6) : _metroSelectedColor,
          width: active ? 4 : 3,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: active ? 0.6 : 0.45),
            blurRadius: active ? 6 : 4,
          ),
        ],
      ),
    );
    return Center(
      child: isArc ? Transform.rotate(angle: math.pi / 4, child: dot) : dot,
    );
  }
}

class _PoiMarker extends StatelessWidget {
  const _PoiMarker({
    required this.icon,
    required this.color,
    required this.selected,
  });

  final IconData icon;
  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Colors.black.withValues(alpha: 0.78),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : color,
            width: selected ? 2.5 : 2,
          ),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3)],
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      );
}

class _PinGroup {
  const _PinGroup(this.key, this.listings, this.point);
  final String key;
  final List<MapListingPoint> listings;
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

  final MapListingPoint listing;
  final Map<String, double>? rates;
  final String? displayCurrency;

  @override
  Widget build(BuildContext context) {
    final ratesOrEmpty = rates ?? const <String, double>{};
    final label = pinPriceLabelValues(
      listing.price,
      listing.currency,
      rates: rates,
      displayCurrency: displayCurrency,
    );
    final color = priceToneColor(
      priceToneForValues(
        price: listing.price,
        currency: listing.currency,
        medianUsd: listing.marketMedianUsd,
        rates: ratesOrEmpty,
      ),
    );
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
    return Center(
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.72), width: 2),
        ),
      ),
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
    required this.onPreviousPage,
    required this.onNextPage,
    required this.onClose,
  });

  final List<MapListingPoint> items;
  final int pageIndex;
  final int pageCount;
  final Map<String, double>? rates;
  final String? displayCurrency;
  final void Function(MapListingPoint) onTapListing;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    const size = 280.0;
    const center = size / 2;
    final radius = pageCount > 1
        ? 104.0
        : switch (items.length) {
            <= 4 => 66.0,
            <= 7 => 84.0,
            _ => 104.0,
          };
    return SizedBox(
      key: const Key('map-listing-group-page'),
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
                left: center + math.cos(angle) * radius - 24,
                top: center + math.sin(angle) * radius - 24,
                child: _RadialPriceDot(
                  key: Key('map-listing-page-item-${items[i].key}'),
                  listing: items[i],
                  rates: rates,
                  displayCurrency: displayCurrency,
                  onTap: () => onTapListing(items[i]),
                ),
              );
            }(),
          Positioned(
            left: center - 18,
            top: center - 18,
            child: _RadialHub(onClose: onClose),
          ),
          if (pageCount > 1)
            Positioned(
              left: center - 59,
              top: center + 28,
              child: _RadialPager(
                pageIndex: pageIndex,
                pageCount: pageCount,
                onPreviousPage: onPreviousPage,
                onNextPage: onNextPage,
              ),
            ),
        ],
      ),
    );
  }
}

class _RadialHub extends StatelessWidget {
  const _RadialHub({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Material(
      color: color,
      shape: const CircleBorder(),
      elevation: 8,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onClose,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: const Icon(Icons.close, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

class _RadialPager extends StatelessWidget {
  const _RadialPager({
    required this.pageIndex,
    required this.pageCount,
    required this.onPreviousPage,
    required this.onNextPage,
  });

  final int pageIndex;
  final int pageCount;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.80),
      borderRadius: BorderRadius.circular(18),
      elevation: 6,
      child: Container(
        width: 118,
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          children: [
            _RadialPagerButton(icon: Icons.chevron_left, onTap: onPreviousPage),
            Expanded(
              child: Center(
                child: Text(
                  '${pageIndex + 1}/$pageCount',
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            _RadialPagerButton(
              key: const Key('map-listing-page-next'),
              icon: Icons.chevron_right,
              onTap: onNextPage,
            ),
          ],
        ),
      ),
    );
  }
}

class _RadialPagerButton extends StatelessWidget {
  const _RadialPagerButton({
    super.key,
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 30,
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: Icon(
          icon,
          size: 19,
          color: onTap == null ? Colors.white30 : Colors.white,
        ),
      ),
    );
  }
}

class _RadialPriceDot extends StatelessWidget {
  const _RadialPriceDot({
    super.key,
    required this.listing,
    required this.rates,
    required this.displayCurrency,
    required this.onTap,
  });

  final MapListingPoint listing;
  final Map<String, double>? rates;
  final String? displayCurrency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ratesOrEmpty = rates ?? const <String, double>{};
    final color = priceToneColor(
      priceToneForValues(
        price: listing.price,
        currency: listing.currency,
        medianUsd: listing.marketMedianUsd,
        rates: ratesOrEmpty,
      ),
    );
    final price = pinPriceLabelValues(
      listing.price,
      listing.currency,
      rates: rates,
      displayCurrency: displayCurrency,
    );
    return Material(
      color: color.withValues(alpha: 0.97),
      shape: const CircleBorder(),
      elevation: 6,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              price,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                shadows: [Shadow(color: Colors.black38, blurRadius: 2)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

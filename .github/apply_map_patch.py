from pathlib import Path
import re


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"missing replacement anchor: {label}")
    return text.replace(old, new, 1)


home_path = Path("app/lib/screens/home_screen.dart")
home = home_path.read_text()
home = replace_once(
    home,
    "import '../widgets/map_view.dart';\n",
    "import '../widgets/map_view.dart';\nimport '../widgets/quick_presets_bar.dart';\n",
    "home quick presets import",
)
home, compact_count = re.subn(
    r"\n  Future<void> _applyCompactFilters\(AppState state, Filters filters\) async \{.*?\n  \}\n",
    "\n",
    home,
    count=1,
    flags=re.S,
)
if compact_count != 1:
    raise SystemExit(f"compact filters removal count={compact_count}")

body_pattern = re.compile(
    r"      body: Column\(\n        children: \[.*?\n      \),\n      floatingActionButton:",
    re.S,
)
body_replacement = """      body: Stack(
        children: [
          Column(
            children: [
              QuickPresetsBar(
                onApply: (filters) async {
                  state.updateFilters(filters);
                  await state.search();
                  if (_mapMode) await state.loadMapListings();
                },
                onManage: _openPresets,
              ),
              _SummaryBar(state: state, settings: settings),
              if (state.degradedCountries.isNotEmpty)
                _Banner(
                  text: settings.t('demoBanner', {
                    'countries': state.degradedCountries.join(', '),
                  }),
                ),
              if (state.sourceErrors.isNotEmpty)
                _SourceErrorBanner(
                  errors: state.sourceErrors,
                  settings: settings,
                ),
              Expanded(child: _body(state, settings, hidden)),
            ],
          ),
          if (state.loading || state.mapLoading)
            Positioned.fill(
              child: _DataLoadingOverlay(
                label: settings.lang == 'ru'
                    ? 'Загружаем данные…'
                    : 'Loading data…',
              ),
            ),
        ],
      ),
      floatingActionButton:"""
home, body_count = body_pattern.subn(body_replacement, home, count=1)
if body_count != 1:
    raise SystemExit(f"home body replacement count={body_count}")

loading_class = """class _DataLoadingOverlay extends StatelessWidget {
  const _DataLoadingOverlay({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AbsorbPointer(
      absorbing: true,
      child: ColoredBox(
        color: scheme.scrim.withValues(alpha: 0.28),
        child: Center(
          child: Card(
            elevation: 10,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

"""
home = replace_once(
    home,
    "class _SummaryBar extends StatelessWidget {",
    loading_class + "class _SummaryBar extends StatelessWidget {",
    "loading overlay class",
)
home_path.write_text(home)

map_path = Path("app/lib/widgets/map_view.dart")
src = map_path.read_text()

src = replace_once(
    src,
    "    setState(() => _zones = zones);\n\n    // A city typed/selected in filters is an explicit geographic scope, so it\n",
    "    setState(() => _zones = zones);\n\n    // Filters and map share one canonical selection. If a saved preset, filter\n    // sheet or deep link already selected a zone, restore it immediately and\n    // center the map on the same catalog entity.\n    if (_syncSelectionFromFilters(focus: true)) return;\n\n    // A city typed/selected in filters is an explicit geographic scope, so it\n",
    "load zones sync",
)

helpers = """  DistrictZone? _zoneByName(Iterable<DistrictZone> zones, String name) {
    if (name.isEmpty) return null;
    for (final zone in zones) {
      if (zone.name == name) return zone;
    }
    return null;
  }

  DistrictZone? _zoneMatchingFilters() {
    final filters = context.read<AppState>().filters;
    return _zoneByName(_zones.metroStations, filters.metro) ??
        _zoneByName(_zones.areaZones, filters.area) ??
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
    if (!mounted || _zones.all.isEmpty) return false;
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

"""
src = replace_once(
    src,
    "  Future<void> _applyZoneScope(DistrictZone zone) async {\n",
    helpers + "  Future<void> _applyZoneScope(DistrictZone zone, {num? metroRadiusM}) async {\n",
    "map sync helpers",
)

src = replace_once(
    src,
    "      'metro' => scoped.copyWith(metro: zone.name),\n",
    "      'metro' => scoped.copyWith(\n        metro: zone.name,\n        metroMaxM: metroRadiusM,\n      ),\n",
    "metro radius scope",
)

old_select = """  Future<void> _selectZone(DistrictZone zone) async {
    final district = _ancestorOfType(zone, 'district');
    setState(() {
      _selectedZoneId = zone.id;
      _selectedDistrictId = district?.id;
      _activeZoneFocusId = zone.id;
      _expandedGroupKey = null;
    });
    _focusZone(zone);
    await _applyZoneScope(zone);
  }
"""
new_select = """  Future<void> _clearZoneScope(DistrictZone zone) async {
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
      'metro' => current.copyWith(metro: '', clearMetroMaxM: true),
      _ => current,
    };
    state.updateFilters(next);
    await state.search();
    if (!mounted) return;
    await state.loadMapListings();
  }

  Future<void> _selectZone(
    DistrictZone zone, {
    num? metroRadiusM,
  }) async {
    final current = context.read<AppState>().filters;
    final sameZone = _selectedZoneId == zone.id;
    final sameMetroRadius = zone.type != 'metro' ||
        metroRadiusM == null ||
        current.metroMaxM == metroRadiusM;
    if (sameZone && sameMetroRadius) {
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
    await _applyZoneScope(zone, metroRadiusM: metroRadiusM);
  }
"""
src = replace_once(src, old_select, new_select, "toggle zone selection")

hit_helpers = """  double _distanceM(LatLng a, LatLng b) {
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

  void _handlePointTap(LatLng point, VoidCallback action) {
    if (_drawing) {
      setState(() => _area.add(point));
      return;
    }
    action();
  }

"""
src = replace_once(
    src,
    "  void _onMapTap(LatLng point) {\n",
    hit_helpers + "  void _onMapTap(LatLng point) {\n",
    "metro hit helpers",
)

src = replace_once(
    src,
    "    if (_drawing) {\n      setState(() => _area.add(point));\n      return;\n    }\n\n    // Hit-test narrow geographic scopes before broad districts. This prevents\n",
    "    if (_drawing) {\n      setState(() => _area.add(point));\n      return;\n    }\n\n    if (_showMetro) {\n      final metroHit = _metroHit(point);\n      if (metroHit != null) {\n        unawaited(_selectZone(metroHit.$1, metroRadiusM: metroHit.$2));\n        return;\n      }\n    }\n\n    // Hit-test narrow geographic scopes before broad districts. This prevents\n",
    "metro map hit testing",
)

src = replace_once(
    src,
    "  Polygon _proximityRing(DistrictZone place, double radiusM, Color color) {\n    return Polygon(\n      points: _circleRing(place, radiusM),\n      borderStrokeWidth: 1.5,\n      borderColor: color.withValues(alpha: 0.78),\n      color: color.withValues(alpha: 0.075),\n    );\n  }\n",
    "  Polygon _proximityRing(\n    DistrictZone place,\n    double radiusM,\n    Color color, {\n    bool selected = false,\n  }) {\n    return Polygon(\n      points: _circleRing(place, radiusM),\n      borderStrokeWidth: selected ? 3 : 1.5,\n      borderColor: color.withValues(alpha: selected ? 1 : 0.78),\n      color: color.withValues(alpha: selected ? 0.18 : 0.075),\n    );\n  }\n",
    "selected proximity ring",
)

src = replace_once(
    src,
    "            onTap: () => widget.onTapListing(listing),\n",
    "            onTap: () => _handlePointTap(\n              group.point,\n              () => widget.onTapListing(listing),\n            ),\n",
    "listing drawing priority",
)
src = replace_once(
    src,
    "          onTap: () => _openGroup(group),\n",
    "          onTap: () => _handlePointTap(group.point, () => _openGroup(group)),\n",
    "cluster drawing priority",
)
src = replace_once(
    src,
    "          onTap: () => unawaited(_selectZone(poi)),\n",
    "          onTap: () => _handlePointTap(\n            LatLng(poi.lat, poi.lng),\n            () => unawaited(_selectZone(poi)),\n          ),\n",
    "poi drawing priority",
)
src = replace_once(
    src,
    "                        onTap: () => unawaited(_selectZone(station)),\n",
    "                        onTap: () => _handlePointTap(\n                          LatLng(station.lat, station.lng),\n                          () => unawaited(_selectZone(station)),\n                        ),\n",
    "metro marker drawing priority",
)

src = replace_once(
    src,
    "    final s = context.watch<SettingsState>().s;\n    final visible = _visible;\n",
    "    final s = context.watch<SettingsState>().s;\n    final appState = context.watch<AppState>();\n    final selectedMetroRadius = appState.filters.metroMaxM?.toDouble();\n    final desiredZone = _zoneMatchingFilters();\n    if (desiredZone?.id != _selectedZoneId) {\n      WidgetsBinding.instance.addPostFrameCallback((_) {\n        if (mounted) _syncSelectionFromFilters(focus: true);\n      });\n    }\n    final visible = _visible;\n",
    "build filter sync",
)

src = replace_once(
    src,
    "                  for (final station in _zones.metroStations)\n                    _proximityRing(station, 1000, _metro1000Color),\n                  for (final station in _zones.metroStations)\n                    _proximityRing(station, 500, _metro500Color),\n                  for (final station in _zones.metroStations)\n                    _proximityRing(station, 200, _metro200Color),\n",
    "                  for (final station in _zones.metroStations)\n                    _proximityRing(\n                      station,\n                      1000,\n                      _metro1000Color,\n                      selected: station.id == _selectedZoneId &&\n                          selectedMetroRadius == 1000,\n                    ),\n                  for (final station in _zones.metroStations)\n                    _proximityRing(\n                      station,\n                      500,\n                      _metro500Color,\n                      selected: station.id == _selectedZoneId &&\n                          selectedMetroRadius == 500,\n                    ),\n                  for (final station in _zones.metroStations)\n                    _proximityRing(\n                      station,\n                      200,\n                      _metro200Color,\n                      selected: station.id == _selectedZoneId &&\n                          selectedMetroRadius == 200,\n                    ),\n",
    "metro selected rings",
)

src = replace_once(
    src,
    "            if (selectedZone != null && selectedZone.type != 'district')\n",
    "            if (selectedZone != null)\n",
    "selected zone label",
)

map_path.write_text(src)

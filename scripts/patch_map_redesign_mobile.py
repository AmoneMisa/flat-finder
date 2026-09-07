from pathlib import Path
import re

path = Path('app/lib/widgets/map_view.dart')
s = path.read_text()


def replace_once(old: str, new: str, name: str) -> None:
    global s
    count = s.count(old)
    if count != 1:
        raise SystemExit(f'{name}: expected 1 occurrence, found {count}')
    s = s.replace(old, new)


def sub_once(pattern: str, repl: str, name: str, flags: int = 0) -> None:
    global s
    s2, count = re.subn(pattern, repl, s, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f'{name}: expected 1 regex match, found {count}')
    s = s2

# One selected/proximity radius at a time; no three discovery rings.
replace_once(
"""const _metro200Color = Color(0xFF10B981);
const _metro500Color = Color(0xFFD99A0B);
const _metro1000Color = Color(0xFF8B5CF6);
// The chosen wedge's own color, distinct from the three discovery-mode
// presets above -- matches the pink accent the web client's equivalent
// shape uses.
const _metroSelectedColor = Color(0xFFE0679A);
""",
"""const _metroSelectedColor = Color(0xFFE0679A);
const _neutralMapMarker = Color(0xE61A1F2B);
""",
'constants',
)

replace_once(
"""  bool _showMetro = false;
  bool _showParks = false;
  bool _showShoppingMalls = false;
  bool _showUniversities = false;
""",
"""  bool _showMetro = false;
  bool _showBus = false;
  bool _showTram = false;
  bool _showTrolleybus = false;
  bool _showMinibus = false;
  bool _showParks = false;
  bool _showShoppingMalls = false;
  bool _showUniversities = false;
  bool _showSchools = false;
  bool _showResidentialComplexes = false;
  bool _showAirports = false;
  bool _showRailwayStations = false;
  bool _showBusStations = false;
  bool _showParkings = false;

  double _busRadiusM = 500;
  double _tramRadiusM = 500;
  double _trolleybusRadiusM = 500;
  double _minibusRadiusM = 500;
  double _parkRadiusM = 500;
  double _mallRadiusM = 500;
  double _universityRadiusM = 500;
  double _schoolRadiusM = 300;
  double _airportRadiusM = 2000;
  double _railwayRadiusM = 1000;
  double _busStationRadiusM = 1000;
  double _parkingRadiusM = 300;
""",
'layer state',
)

# Extend map hit-testing so enabled POI/transport icons are interactive.
replace_once(
"""      if (_showParks || _showShoppingMalls || _showUniversities)
        _hitZone(point, <DistrictZone>[
          if (_showParks) ..._zones.parks,
          if (_showShoppingMalls) ..._zones.shoppingMalls,
          if (_showUniversities) ..._zones.universities,
        ]),
""",
"""      if (_showParks || _showShoppingMalls || _showUniversities ||
          _showSchools || _showResidentialComplexes || _showAirports ||
          _showRailwayStations || _showBusStations || _showParkings ||
          _showBus || _showTram || _showTrolleybus || _showMinibus)
        _hitZone(point, <DistrictZone>[
          if (_showParks) ..._zones.parks,
          if (_showShoppingMalls) ..._zones.shoppingMalls,
          if (_showUniversities) ..._zones.universities,
          if (_showSchools) ..._zones.schools,
          if (_showResidentialComplexes) ..._zones.residentialComplexes,
          if (_showAirports) ..._zones.airports,
          if (_showRailwayStations) ..._zones.railwayStations,
          if (_showBusStations) ..._zones.busStations,
          if (_showParkings) ..._zones.parkings,
          if (_showBus) ..._zones.transport('bus'),
          if (_showTram) ..._zones.transport('tram'),
          if (_showTrolleybus) ..._zones.transport('trolleybus'),
          if (_showMinibus) ..._zones.transport('minibus'),
        ]),
""",
'hit testing',
)

# The redundant frame-results action is intentionally removed from the redesign.
sub_once(
    r"\n  /// The manual \"frame my results\" action behind the fit button\..*?\n  double _worldWidth",
    "\n  double _worldWidth",
    'fit results method',
    re.S,
)

# Price quality for count clusters: dark center + semantic ring.
replace_once(
"""          child: _ClusterDot(count: group.listings.length),
""",
"""          child: _ClusterDot(
            count: group.listings.length,
            tone: _priceToneForGroup(group.listings),
          ),
""",
'cluster tone call',
)

# Add helpers before metro-distance hit testing.
anchor = """  double _distanceM(LatLng a, LatLng b) {
"""
helpers = r'''  PriceTone _priceToneForGroup(List<MapListingPoint> listings) {
    if (listings.isEmpty) return PriceTone.pink;
    final scores = <int>[];
    final rates = widget.rates ?? const <String, double>{};
    for (final listing in listings) {
      final tone = priceToneForValues(
        price: listing.price,
        currency: listing.currency,
        medianUsd: listing.marketMedianUsd,
        rates: rates,
      );
      scores.add(tone.index);
    }
    scores.sort();
    return PriceTone.values[scores[scores.length ~/ 2]];
  }

  double _transportRadius(String? mode) => switch (mode) {
        'tram' => _tramRadiusM,
        'trolleybus' => _trolleybusRadiusM,
        'minibus' => _minibusRadiusM,
        _ => _busRadiusM,
      };

  bool _transportVisible(String? mode) => switch (mode) {
        'bus' => _showBus,
        'tram' => _showTram,
        'trolleybus' => _showTrolleybus,
        'minibus' => _showMinibus,
        _ => false,
      };

  IconData _transportIcon(String? mode) => switch (mode) {
        'tram' => Icons.tram_outlined,
        'trolleybus' => Icons.electric_bus_outlined,
        'minibus' => Icons.airport_shuttle_outlined,
        _ => Icons.directions_bus_outlined,
      };

  List<DistrictZone> get _visibleTransportStops => _zones.transportStops
      .where((stop) => _transportVisible(stop.mode))
      .toList(growable: false);

  List<Marker> _transportMarkers() => [
        for (final stop in _visibleTransportStops)
          Marker(
            point: LatLng(stop.lat, stop.lng),
            width: 48,
            height: 48,
            child: Semantics(
              button: true,
              label: stop.routeRefs.isEmpty
                  ? stop.label
                  : '${stop.label}: ${stop.routeRefs.join(', ')}',
              child: ExcludeSemantics(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _handlePointTap(
                    LatLng(stop.lat, stop.lng),
                    () => _focusZone(stop),
                  ),
                  child: _PoiMarker(
                    icon: _transportIcon(stop.mode),
                    color: _parseHexColor(stop.colorHex),
                    selected: false,
                  ),
                ),
              ),
            ),
          ),
      ];

  String _mapCopy(BuildContext context, String ru, String en) =>
      Localizations.localeOf(context).languageCode.toLowerCase().startsWith('ru')
          ? ru
          : en;

  Future<void> _openLayerSheet(_MapLayerGroup group) async {
    final s = context.read<SettingsState>().s;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          void update(VoidCallback action) {
            setState(action);
            setSheetState(() {});
          }

          Widget toggle({
            required String label,
            required IconData icon,
            required bool value,
            required bool available,
            required ValueChanged<bool> onChanged,
            double? radius,
            ValueChanged<double>? onRadius,
          }) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile.adaptive(
                  secondary: Icon(icon),
                  title: Text(label),
                  subtitle: available ? null : Text(_mapCopy(context, 'нет данных', 'no data')),
                  value: available && value,
                  onChanged: available ? onChanged : null,
                ),
                if (available && value && radius != null && onRadius != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(56, 0, 20, 8),
                    child: Row(
                      children: [
                        Text(_mapCopy(context, 'Радиус', 'Radius')),
                        const Spacer(),
                        DropdownButton<double>(
                          value: radius,
                          items: const [200.0, 500.0, 1000.0, 2000.0]
                              .map((value) => DropdownMenuItem(
                                    value: value,
                                    child: Text('${value.round()} m'),
                                  ))
                              .toList(growable: false),
                          onChanged: (value) {
                            if (value != null) onRadius(value);
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            );
          }

          final children = <Widget>[];
          if (group == _MapLayerGroup.territories) {
            children.addAll([
              toggle(label: s.t('city'), icon: Icons.location_city_outlined, value: _showCity, available: _zones.cityZone != null, onChanged: (v) => update(() => _showCity = v)),
              toggle(label: s.t('districts'), icon: Icons.layers_outlined, value: _showDistricts, available: _zones.districtZones.isNotEmpty, onChanged: (v) => update(() => _showDistricts = v)),
              toggle(label: s.t('microdistricts'), icon: Icons.grid_view_outlined, value: _showMicrodistricts, available: _zones.microdistrictMarkers.isNotEmpty, onChanged: (v) => update(() => _showMicrodistricts = v)),
              toggle(label: s.t('quartals'), icon: Icons.dashboard_outlined, value: _showQuartals, available: _zones.quartalMarkers.isNotEmpty, onChanged: (v) => update(() => _showQuartals = v)),
              toggle(label: s.t('areas'), icon: Icons.map_outlined, value: _showAreas, available: _zones.areaZones.isNotEmpty, onChanged: (v) => update(() => _showAreas = v)),
            ]);
          } else if (group == _MapLayerGroup.transport) {
            children.addAll([
              toggle(label: s.t('metro'), icon: Icons.subway_outlined, value: _showMetro, available: _zones.metroStations.isNotEmpty, onChanged: (v) => update(() => _showMetro = v), radius: _shapeRadiusM(context.read<AppState>().filters).toDouble(), onRadius: (v) {
                final state = context.read<AppState>();
                update(() {});
                state.updateFilters(state.filters.copyWith(metroMaxM: v));
                unawaited(state.search().then((_) => state.loadMapListings()));
              }),
              toggle(label: _mapCopy(context, 'Автобусы', 'Bus'), icon: Icons.directions_bus_outlined, value: _showBus, available: _zones.transport('bus').isNotEmpty, onChanged: (v) => update(() => _showBus = v), radius: _busRadiusM, onRadius: (v) => update(() => _busRadiusM = v)),
              toggle(label: _mapCopy(context, 'Трамвай', 'Tram'), icon: Icons.tram_outlined, value: _showTram, available: _zones.transport('tram').isNotEmpty, onChanged: (v) => update(() => _showTram = v), radius: _tramRadiusM, onRadius: (v) => update(() => _tramRadiusM = v)),
              toggle(label: _mapCopy(context, 'Троллейбус', 'Trolleybus'), icon: Icons.electric_bus_outlined, value: _showTrolleybus, available: _zones.transport('trolleybus').isNotEmpty, onChanged: (v) => update(() => _showTrolleybus = v), radius: _trolleybusRadiusM, onRadius: (v) => update(() => _trolleybusRadiusM = v)),
              toggle(label: _mapCopy(context, 'Маршрутки', 'Minibus'), icon: Icons.airport_shuttle_outlined, value: _showMinibus, available: _zones.transport('minibus').isNotEmpty, onChanged: (v) => update(() => _showMinibus = v), radius: _minibusRadiusM, onRadius: (v) => update(() => _minibusRadiusM = v)),
            ]);
          } else {
            children.addAll([
              toggle(label: _mapCopy(context, 'ЖК', 'Residential complexes'), icon: Icons.apartment_outlined, value: _showResidentialComplexes, available: _zones.residentialComplexes.isNotEmpty, onChanged: (v) => update(() => _showResidentialComplexes = v)),
              toggle(label: _mapCopy(context, 'Школы', 'Schools'), icon: Icons.school_outlined, value: _showSchools, available: _zones.schools.isNotEmpty, onChanged: (v) => update(() => _showSchools = v), radius: _schoolRadiusM, onRadius: (v) => update(() => _schoolRadiusM = v)),
              toggle(label: s.t('shoppingMalls'), icon: Icons.local_mall_outlined, value: _showShoppingMalls, available: _zones.shoppingMalls.isNotEmpty, onChanged: (v) => update(() => _showShoppingMalls = v), radius: _mallRadiusM, onRadius: (v) => update(() => _mallRadiusM = v)),
              toggle(label: s.t('parks'), icon: Icons.park_outlined, value: _showParks, available: _zones.parks.isNotEmpty, onChanged: (v) => update(() => _showParks = v), radius: _parkRadiusM, onRadius: (v) => update(() => _parkRadiusM = v)),
              toggle(label: s.t('universities'), icon: Icons.account_balance_outlined, value: _showUniversities, available: _zones.universities.isNotEmpty, onChanged: (v) => update(() => _showUniversities = v), radius: _universityRadiusM, onRadius: (v) => update(() => _universityRadiusM = v)),
              toggle(label: _mapCopy(context, 'Парковки', 'Parking'), icon: Icons.local_parking_outlined, value: _showParkings, available: _zones.parkings.isNotEmpty, onChanged: (v) => update(() => _showParkings = v), radius: _parkingRadiusM, onRadius: (v) => update(() => _parkingRadiusM = v)),
              toggle(label: _mapCopy(context, 'Аэропорт', 'Airport'), icon: Icons.flight_outlined, value: _showAirports, available: _zones.airports.isNotEmpty, onChanged: (v) => update(() => _showAirports = v), radius: _airportRadiusM, onRadius: (v) => update(() => _airportRadiusM = v)),
              toggle(label: _mapCopy(context, 'Ж/д вокзал', 'Railway station'), icon: Icons.train_outlined, value: _showRailwayStations, available: _zones.railwayStations.isNotEmpty, onChanged: (v) => update(() => _showRailwayStations = v), radius: _railwayRadiusM, onRadius: (v) => update(() => _railwayRadiusM = v)),
              toggle(label: _mapCopy(context, 'Автовокзалы', 'Bus stations'), icon: Icons.departure_board_outlined, value: _showBusStations, available: _zones.busStations.isNotEmpty, onChanged: (v) => update(() => _showBusStations = v), radius: _busStationRadiusM, onRadius: (v) => update(() => _busStationRadiusM = v)),
            ]);
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Text(
                      switch (group) {
                        _MapLayerGroup.territories => _mapCopy(context, 'Территории', 'Territories'),
                        _MapLayerGroup.transport => _mapCopy(context, 'Транспорт', 'Transport'),
                        _MapLayerGroup.poi => _mapCopy(context, 'Объекты и сервисы', 'Places & services'),
                      },
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  ...children,
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  double _distanceM(LatLng a, LatLng b) {
'''
replace_once(anchor, helpers, 'helper insertion')

# Remove discovery-mode metro rings entirely.
sub_once(
    r"\n                // Presets while nothing is picked yet \(discovery mode\);.*?\n                if \(_showMetro &&\n                    _selectedMetroStations\(filters\)\.isNotEmpty\)",
    "\n                if (_showMetro &&\n                    _selectedMetroStations(filters).isNotEmpty)",
    'metro discovery rings',
    re.S,
)

# Replace three POI radii with one selected radius and add new POIs/transport.
sub_once(
    r"\n                if \(_showParks && _zones\.parks\.isNotEmpty\).*?\n                if \(_showDistricts && _zones\.districtZones\.isNotEmpty\)",
    r'''
                if (_showParks && _zones.parks.isNotEmpty)
                  PolygonLayer(polygons: [
                    for (final poi in _zones.parks) _proximityRing(poi, _parkRadiusM, _parseHexColor(poi.colorHex)),
                    for (final poi in _zones.parks) for (final ring in poi.boundaryRings) _zonePolygon(poi, ring, fillAlpha: 0.10),
                  ]),
                if (_showShoppingMalls && _zones.shoppingMalls.isNotEmpty)
                  PolygonLayer(polygons: [
                    for (final poi in _zones.shoppingMalls) _proximityRing(poi, _mallRadiusM, _parseHexColor(poi.colorHex)),
                    for (final poi in _zones.shoppingMalls) for (final ring in poi.boundaryRings) _zonePolygon(poi, ring, fillAlpha: 0.09),
                  ]),
                if (_showUniversities && _zones.universities.isNotEmpty)
                  PolygonLayer(polygons: [
                    for (final poi in _zones.universities) _proximityRing(poi, _universityRadiusM, _parseHexColor(poi.colorHex)),
                    for (final poi in _zones.universities) for (final ring in poi.boundaryRings) _zonePolygon(poi, ring, fillAlpha: 0.09),
                  ]),
                if (_showSchools && _zones.schools.isNotEmpty)
                  PolygonLayer(polygons: [for (final poi in _zones.schools) _proximityRing(poi, _schoolRadiusM, _parseHexColor(poi.colorHex))]),
                if (_showAirports && _zones.airports.isNotEmpty)
                  PolygonLayer(polygons: [for (final poi in _zones.airports) _proximityRing(poi, _airportRadiusM, _parseHexColor(poi.colorHex))]),
                if (_showRailwayStations && _zones.railwayStations.isNotEmpty)
                  PolygonLayer(polygons: [for (final poi in _zones.railwayStations) _proximityRing(poi, _railwayRadiusM, _parseHexColor(poi.colorHex))]),
                if (_showBusStations && _zones.busStations.isNotEmpty)
                  PolygonLayer(polygons: [for (final poi in _zones.busStations) _proximityRing(poi, _busStationRadiusM, _parseHexColor(poi.colorHex))]),
                if (_showParkings && _zones.parkings.isNotEmpty)
                  PolygonLayer(polygons: [for (final poi in _zones.parkings) _proximityRing(poi, _parkingRadiusM, _parseHexColor(poi.colorHex))]),
                if (_visibleTransportStops.isNotEmpty)
                  PolygonLayer(polygons: [for (final stop in _visibleTransportStops) _proximityRing(stop, _transportRadius(stop.mode), _parseHexColor(stop.colorHex))]),
                if (_showDistricts && _zones.districtZones.isNotEmpty)''',
    'poi ring block',
    re.S,
)

# Metro marker gets canonical line colours.
replace_once(
"""                                child: _MetroStationMarker(
                                  selected:
                                      filters.metro.contains(station.name),
                                  dimmed: filters.metro.isNotEmpty &&
                                      !filters.metro.contains(
                                        station.name,
                                      ),
                                ),
""",
"""                                child: _MetroStationMarker(
                                  selected: filters.metro.contains(station.name),
                                  dimmed: filters.metro.isNotEmpty &&
                                      !filters.metro.contains(station.name),
                                  lineColors: [
                                    for (final color in station.lineColorHexes)
                                      _parseHexColor(color),
                                    if (station.lineColorHexes.isEmpty && station.lineColorHex != null)
                                      _parseHexColor(station.lineColorHex!),
                                  ],
                                ),
""",
'metro marker call',
)

# Add expanded POI/transport markers after universities.
needle = """                if (_showUniversities && _zones.universities.isNotEmpty)
                  MarkerLayer(
                    markers: _poiMarkers(
                      _zones.universities,
                      Icons.school_outlined,
                    ),
                  ),
"""
extra_markers = needle + """                if (_showSchools && _zones.schools.isNotEmpty)
                  MarkerLayer(markers: _poiMarkers(_zones.schools, Icons.school_outlined)),
                if (_showResidentialComplexes && _zones.residentialComplexes.isNotEmpty)
                  MarkerLayer(markers: _poiMarkers(_zones.residentialComplexes, Icons.apartment_outlined)),
                if (_showAirports && _zones.airports.isNotEmpty)
                  MarkerLayer(markers: _poiMarkers(_zones.airports, Icons.flight_outlined)),
                if (_showRailwayStations && _zones.railwayStations.isNotEmpty)
                  MarkerLayer(markers: _poiMarkers(_zones.railwayStations, Icons.train_outlined)),
                if (_showBusStations && _zones.busStations.isNotEmpty)
                  MarkerLayer(markers: _poiMarkers(_zones.busStations, Icons.departure_board_outlined)),
                if (_showParkings && _zones.parkings.isNotEmpty)
                  MarkerLayer(markers: _poiMarkers(_zones.parkings, Icons.local_parking_outlined)),
                if (_visibleTransportStops.isNotEmpty)
                  MarkerLayer(markers: _transportMarkers()),
"""
replace_once(needle, extra_markers, 'extra markers')

# Remove the manual frame-results FAB.
sub_once(
    r"\n              // Panning away from the results used to be one-way:.*?\n              FloatingActionButton\.small\(\n                heroTag: 'draw',",
    "\n              FloatingActionButton.small(\n                heroTag: 'draw',",
    'fit results fab',
    re.S,
)

# Replace the long horizontal chip strip + old metro legend with three compact grouped buttons.
sub_once(
    r"\n        if \(_zones\.cityZone\?\.boundaryRings\.isNotEmpty == true \|\|.*?\n        if \(\(_showMetro && _zones\.metroStations\.isNotEmpty\) \|\|.*?_MetroLegend\(s: s\)\),",
    r'''
        Positioned(
          left: 12,
          top: _drawing || _area.length >= 3 ? 56 : 12,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MapLayerButton(
                tooltip: _mapCopy(context, 'Территории', 'Territories'),
                icon: Icons.layers_outlined,
                active: _showCity || _showDistricts || _showMicrodistricts || _showQuartals || _showAreas,
                onTap: () => _openLayerSheet(_MapLayerGroup.territories),
              ),
              const SizedBox(width: 6),
              _MapLayerButton(
                tooltip: _mapCopy(context, 'Транспорт', 'Transport'),
                icon: Icons.train_outlined,
                active: _showMetro || _showBus || _showTram || _showTrolleybus || _showMinibus,
                onTap: () => _openLayerSheet(_MapLayerGroup.transport),
              ),
              const SizedBox(width: 6),
              _MapLayerButton(
                tooltip: _mapCopy(context, 'Объекты и сервисы', 'Places & services'),
                icon: Icons.place_outlined,
                active: _showParks || _showShoppingMalls || _showUniversities || _showSchools || _showResidentialComplexes || _showAirports || _showRailwayStations || _showBusStations || _showParkings,
                onTap: () => _openLayerSheet(_MapLayerGroup.poi),
              ),
            ],
          ),
        ),
        Positioned(
          left: 12,
          bottom: 12,
          child: _PriceLegend(copy: _mapCopy),
        ),''',
    'layer control strip',
    re.S,
)

# Replace old control/legend classes with compact group button + semantic price legend.
sub_once(
    r"\nclass _ZoneToggle extends StatelessWidget \{.*?\nclass _MetroStationMarker extends StatelessWidget \{",
    r'''
enum _MapLayerGroup { territories, transport, poi }

class _MapLayerButton extends StatelessWidget {
  const _MapLayerButton({required this.tooltip, required this.icon, required this.active, required this.onTap});
  final String tooltip;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: active,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: active ? scheme.primaryContainer : scheme.surface.withValues(alpha: 0.94),
          elevation: 4,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 42,
              height: 42,
              child: Icon(icon, size: 20, color: active ? scheme.onPrimaryContainer : scheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}

class _PriceLegend extends StatelessWidget {
  const _PriceLegend({required this.copy});
  final String Function(BuildContext context, String ru, String en) copy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LegendItem(color: priceToneColor(PriceTone.green), label: copy(context, 'выгодно', 'good')),
            const SizedBox(width: 8),
            _LegendItem(color: priceToneColor(PriceTone.pink), label: copy(context, 'средне', 'average')),
            const SizedBox(width: 8),
            _LegendItem(color: priceToneColor(PriceTone.red), label: copy(context, 'дорого', 'high')),
          ],
        ),
      ),
    );
  }
}

class _MetroStationMarker extends StatelessWidget {''',
    'control classes',
    re.S,
)

# Update metro marker class body to segmented line border and M badge.
sub_once(
    r"class _MetroStationMarker extends StatelessWidget \{.*?\n\}\n\n/// The distance grip",
    r'''class _MetroStationMarker extends StatelessWidget {
  const _MetroStationMarker({required this.selected, required this.lineColors, this.dimmed = false});
  final bool selected;
  final bool dimmed;
  final List<Color> lineColors;

  @override
  Widget build(BuildContext context) {
    final colors = lineColors.isEmpty ? const [Color(0xFF2563EB)] : lineColors;
    return Center(
      child: Opacity(
        opacity: dimmed ? 0.45 : 1,
        child: CustomPaint(
          painter: _MetroRingPainter(colors: colors, selected: selected),
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: selected ? Theme.of(context).colorScheme.primary : _neutralMapMarker,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: selected ? 2 : 1),
              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3)],
            ),
            child: const Text('M', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
          ),
        ),
      ),
    );
  }
}

class _MetroRingPainter extends CustomPainter {
  const _MetroRingPainter({required this.colors, required this.selected});
  final List<Color> colors;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final sweep = math.pi * 2 / colors.length;
    for (var i = 0; i < colors.length; i++) {
      final paint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 4 : 3;
      canvas.drawArc(rect.deflate(1.5), -math.pi / 2 + sweep * i, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(_MetroRingPainter oldDelegate) =>
      oldDelegate.selected != selected || oldDelegate.colors.join() != colors.join();
}

/// The distance grip''',
    'metro marker class',
    re.S,
)

# Semantic price ring cluster widget.
sub_once(
    r"class _ClusterDot extends StatelessWidget \{.*?\n\}\n\nclass _StandalonePricePin",
    r'''class _ClusterDot extends StatelessWidget {
  const _ClusterDot({required this.count, required this.tone});
  final int count;
  final PriceTone tone;

  @override
  Widget build(BuildContext context) {
    final ring = priceToneColor(tone);
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _neutralMapMarker,
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: 3),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
      ),
      child: count > 1
          ? Text(
              count > 999 ? '999+' : '$count',
              maxLines: 1,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11),
            )
          : null,
    );
  }
}

class _StandalonePricePin''',
    'cluster class',
    re.S,
)

path.write_text(s)

from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, got {count}')
    return text.replace(old, new, 1)


map_path = Path('app/lib/widgets/map_view.dart')
text = map_path.read_text()

text = replace_once(
    text,
    "import '../l10n/review_strings.dart';\n",
    "import '../l10n/review_strings.dart';\nimport '../l10n/strings.dart';\n",
    'AppStrings import',
)

text = replace_once(
    text,
    """  List<Marker> _poiMarkers(List<DistrictZone> pois, IconData icon) => [
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
""",
    """  List<Marker> _poiMarkers(List<DistrictZone> pois, IconData icon) => [
        for (final poi in pois)
          Marker(
            point: LatLng(poi.lat, poi.lng),
            width: 48,
            height: 48,
            child: Semantics(
              button: true,
              selected: poi.id == _selectedZoneId,
              label: poi.label,
              onTap: () => _handlePointTap(
                LatLng(poi.lat, poi.lng),
                () => unawaited(_selectZone(poi)),
              ),
              child: ExcludeSemantics(
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
            ),
          ),
      ];
""",
    'POI 48dp semantics',
)

text = replace_once(
    text,
    """  List<Widget> _metroHandleOverlay(Filters filters) {
""",
    """  List<Widget> _metroHandleOverlay(Filters filters, AppStrings s) {
""",
    'metro handle signature',
)

text = replace_once(
    text,
    """      return Positioned(
        left: point.x - 22,
        top: point.y - 22,
        width: 44,
        height: 44,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => setState(() => _draggingMetroHandle = kind),
          onPanUpdate: (details) =>
              _onMetroHandlePanUpdate(kind, anchor, filters, details),
          onPanEnd: (_) => unawaited(_onMetroHandlePanEnd()),
          onPanCancel: () => setState(() => _draggingMetroHandle = null),
          child: _MetroHandleMarker(
            kind: kind,
            active: _draggingMetroHandle == kind,
          ),
        ),
      );
""",
    """      final semanticLabel = switch (kind) {
        'radius' => s.metroRadiusHandle,
        'from' => s.metroArcStartHandle,
        _ => s.metroArcEndHandle,
      };
      final semanticValue = kind == 'radius'
          ? '${_shapeRadiusM(filters).round()} ${s.metresShort}'
          : '${_handleBearing(filters, kind).round()}°';
      return Positioned(
        left: point.x - 24,
        top: point.y - 24,
        width: 48,
        height: 48,
        child: Semantics(
          label: semanticLabel,
          value: semanticValue,
          hint: s.adjustWithDragOrButtons,
          onIncrease: () => _nudgeMetroHandle(kind, filters, increase: true),
          onDecrease: () => _nudgeMetroHandle(kind, filters, increase: false),
          child: ExcludeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => setState(() => _draggingMetroHandle = kind),
              onPanUpdate: (details) =>
                  _onMetroHandlePanUpdate(kind, anchor, filters, details),
              onPanEnd: (_) => unawaited(_onMetroHandlePanEnd()),
              onPanCancel: () => setState(() => _draggingMetroHandle = null),
              child: _MetroHandleMarker(
                kind: kind,
                active: _draggingMetroHandle == kind,
              ),
            ),
          ),
        ),
      );
""",
    'metro handle accessibility',
)

text = replace_once(
    text,
    """  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsState>().s;
""",
    """  void _nudgeMetroHandle(
    String kind,
    Filters filters, {
    required bool increase,
  }) {
    final state = context.read<AppState>();
    final direction = increase ? 1.0 : -1.0;
    Filters next;
    if (kind == 'radius') {
      final radius = (_shapeRadiusM(filters).toDouble() + direction * 100)
          .clamp(metroMinRadiusM, metroMaxRadiusM)
          .toDouble();
      next = filters.copyWith(metroMaxM: radius);
    } else {
      final from = _shapeBearingFrom(filters)?.toDouble() ?? 270;
      final to = _shapeBearingTo(filters)?.toDouble() ?? 90;
      if (kind == 'from') {
        next = filters.copyWith(
          metroBearingFrom: normalizeBearing(from + direction * 15),
          metroBearingTo: to,
        );
      } else {
        next = filters.copyWith(
          metroBearingFrom: from,
          metroBearingTo: normalizeBearing(to + direction * 15),
        );
      }
    }
    if (!state.updateFilters(next)) return;
    unawaited(() async {
      await state.search();
      if (!mounted) return;
      await state.loadMapListings();
    }());
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsState>().s;
""",
    'semantic metro nudge helper',
)

text = replace_once(
    text,
    """            builder: (context, _, __) => Stack(
              children: _metroHandleOverlay(filters),
            ),
""",
    """            builder: (context, _, __) => Stack(
              children: _metroHandleOverlay(filters, s),
            ),
""",
    'metro handle call',
)

text = replace_once(
    text,
    """                        Marker(
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
                                  filters.metro.contains(station.name),
                              dimmed: filters.metro.isNotEmpty &&
                                  !filters.metro.contains(
                                    station.name,
                                  ),
                            ),
                          ),
                        ),
""",
    """                        Marker(
                          point: LatLng(station.lat, station.lng),
                          width: 48,
                          height: 48,
                          child: Semantics(
                            button: true,
                            selected: filters.metro.contains(station.name),
                            label: station.label,
                            onTap: () => _handlePointTap(
                              LatLng(station.lat, station.lng),
                              () => unawaited(_toggleMetroStation(station)),
                            ),
                            child: ExcludeSemantics(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _handlePointTap(
                                  LatLng(station.lat, station.lng),
                                  () => unawaited(_toggleMetroStation(station)),
                                ),
                                child: _MetroStationMarker(
                                  selected:
                                      filters.metro.contains(station.name),
                                  dimmed: filters.metro.isNotEmpty &&
                                      !filters.metro.contains(
                                        station.name,
                                      ),
                                ),
                              ),
                            ),
                          ),
                        ),
""",
    'metro station 48dp semantics',
)

text = replace_once(
    text,
    """    return Padding(
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
""",
    """    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        onTap: onTap,
        child: ExcludeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: active
                      ? scheme.primary
                      : Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: active ? scheme.primary : Colors.white24,
                  ),
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
          ),
        ),
      ),
    );
""",
    'zone toggle 48dp semantics',
)

text = replace_once(
    text,
    """  Widget build(BuildContext context) {
    return Opacity(
      opacity: dimmed ? 0.45 : 1,
      child: Container(
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
      ),
    );
  }
""",
    """  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 34,
        height: 34,
        child: Opacity(
          opacity: dimmed ? 0.45 : 1,
          child: Container(
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
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 3),
              ],
            ),
            child: const Icon(
              Icons.subway_outlined,
              size: 18,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
""",
    'compact metro visual inside 48dp target',
)

text = replace_once(
    text,
    """  @override
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
""",
    """  @override
  Widget build(BuildContext context) => Center(
        child: SizedBox(
          width: 34,
          height: 34,
          child: Container(
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
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 3),
              ],
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
        ),
      );
""",
    'compact POI visual inside 48dp target',
)

map_path.write_text(text)

l10n_path = Path('app/lib/l10n/review_strings.dart')
l10n = l10n_path.read_text()
l10n = replace_once(
    l10n,
    """  String get kilometresShort => _ru ? 'км' : 'km';
""",
    """  String get kilometresShort => _ru ? 'км' : 'km';
  String get metroRadiusHandle => _ru ? 'Радиус метро' : 'Metro radius';
  String get metroArcStartHandle => _ru ? 'Начало сектора метро' : 'Metro sector start';
  String get metroArcEndHandle => _ru ? 'Конец сектора метро' : 'Metro sector end';
  String get adjustWithDragOrButtons => _ru
      ? 'Перетащите или используйте действия увеличить и уменьшить'
      : 'Drag or use the increase and decrease actions';
""",
    'map accessibility strings',
)
l10n_path.write_text(l10n)

# Cover the new localized semantic copy with a small deterministic unit test.
test_path = Path('app/test/accessibility_l10n_test.dart')
test = test_path.read_text()
test = replace_once(
    test,
    """    expect(ru.kilometresShort, 'км');
    expect(en.kilometresShort, 'km');
""",
    """    expect(ru.kilometresShort, 'км');
    expect(en.kilometresShort, 'km');
    expect(ru.metroRadiusHandle, 'Радиус метро');
    expect(en.metroRadiusHandle, 'Metro radius');
    expect(ru.metroArcStartHandle, 'Начало сектора метро');
    expect(en.metroArcEndHandle, 'Metro sector end');
""",
    'map semantic copy test',
)
test_path.write_text(test)

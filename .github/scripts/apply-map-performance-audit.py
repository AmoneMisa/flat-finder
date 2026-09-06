from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    return text.replace(old, new, 1)


path = Path('app/lib/widgets/map_view.dart')
text = path.read_text(encoding='utf-8')

text = replace_once(
    text,
    "  final GlobalKey _mapAreaKey = GlobalKey();\n",
    "  final GlobalKey _mapAreaKey = GlobalKey();\n"
    "  // Camera panning only changes screen-space metro grip positions. Tick a\n"
    "  // tiny overlay instead of rebuilding all map polygons/markers per frame.\n"
    "  final ValueNotifier<int> _cameraOverlayTick = ValueNotifier<int>(0);\n",
    'camera overlay notifier',
)

text = replace_once(
    text,
    "  String? _groupsCacheKey;\n",
    "  String? _groupsCacheKey;\n"
    "  // Fallback/POI circles are pure geometry. Cache their 65 LatLng points\n"
    "  // instead of repeating trigonometry on unrelated UI rebuilds.\n"
    "  final Map<String, List<LatLng>> _circleRingCache = {};\n",
    'circle ring cache',
)

text = replace_once(
    text,
    "  void dispose() {\n    _cameraAnim.dispose();\n    super.dispose();\n  }\n",
    "  void dispose() {\n    _cameraAnim.dispose();\n    _cameraOverlayTick.dispose();\n    super.dispose();\n  }\n",
    'dispose camera notifier',
)

text = replace_once(
    text,
    "    setState(() => _zones = zones);\n",
    "    setState(() {\n      _zones = zones;\n      _circleRingCache.clear();\n    });\n",
    'clear geometry cache on catalog load',
)

text = replace_once(
    text,
    "      _zones = const MapZones();\n      _loadZones(focusCity: widget.city.isNotEmpty);\n",
    "      _zones = const MapZones();\n      _circleRingCache.clear();\n      _loadZones(focusCity: widget.city.isNotEmpty);\n",
    'clear geometry cache on city change',
)

text = replace_once(
    text,
    "  List<LatLng> _circleRing(DistrictZone zone, [double? radiusM]) =>\n      _circleRingAt(zone.lat, zone.lng, radiusM ?? zone.radiusM);\n",
    "  List<LatLng> _circleRing(DistrictZone zone, [double? radiusM]) {\n"
    "    final radius = radiusM ?? zone.radiusM;\n"
    "    final key = '${zone.id}|${zone.lat}|${zone.lng}|$radius';\n"
    "    return _circleRingCache.putIfAbsent(\n"
    "      key,\n"
    "      () => _circleRingAt(zone.lat, zone.lng, radius),\n"
    "    );\n"
    "  }\n",
    'cache circle rings',
)

text = replace_once(
    text,
    "    final appState = context.watch<AppState>();\n",
    "    final filters = context.select<AppState, Filters>((state) => state.filters);\n",
    'select filters only',
)

count = text.count('appState.filters')
if count != 9:
    raise SystemExit(f'appState.filters replacement: expected 9 matches, found {count}')
text = text.replace('appState.filters', 'filters')

old_position = """                  final trackingHandles =
                      context.read<AppState>().filters.metro.isNotEmpty;
                  if (zoomChanged || closeRadial || trackingHandles) {
                    setState(() {
                      _zoom = z;
                      _expandedGroupKey = null;
                      _expandedGroupPage = 0;
                    });
                  }
"""
new_position = """                  final trackingHandles = filters.metro.isNotEmpty;
                  if (zoomChanged || closeRadial) {
                    setState(() {
                      _zoom = z;
                      _expandedGroupKey = null;
                      _expandedGroupPage = 0;
                    });
                  } else if (trackingHandles) {
                    _cameraOverlayTick.value += 1;
                  }
"""
text = replace_once(text, old_position, new_position, 'camera position rebuild split')

text = replace_once(
    text,
    """        // Above the map, so a grip keeps its own drag instead of losing the
        // gesture to the map's pan recognizer.
        ..._metroHandleOverlay(filters),
""",
    """        // Above the map, so a grip keeps its own drag instead of losing the
        // gesture to the map's pan recognizer. Camera panning ticks only this
        // overlay; the expensive FlutterMap subtree stays intact.
        Positioned.fill(
          child: ValueListenableBuilder<int>(
            valueListenable: _cameraOverlayTick,
            builder: (context, _, __) => Stack(
              children: _metroHandleOverlay(filters),
            ),
          ),
        ),
""",
    'isolated metro handle overlay',
)

path.write_text(text, encoding='utf-8')

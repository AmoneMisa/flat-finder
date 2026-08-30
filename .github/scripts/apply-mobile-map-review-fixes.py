from pathlib import Path
import re


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    return text.replace(old, new, 1)


home_path = Path('app/lib/screens/home_screen.dart')
home = home_path.read_text(encoding='utf-8')

home = replace_once(
    home,
    "import '../state/settings.dart';\n",
    "import '../state/settings.dart';\nimport '../state/sorted.dart';\n",
    'home sorted import',
)

home = replace_once(
    home,
    "    final hidden = context.watch<HiddenState>();\n",
    "    final hidden = context.watch<HiddenState>();\n    final sorted = context.watch<SortedState>();\n",
    'home sorted watch',
)

home = replace_once(
    home,
    "              Expanded(child: _body(state, settings, hidden)),\n",
    "              Expanded(child: _body(state, settings, hidden, sorted)),\n",
    'home body call',
)

home = replace_once(
    home,
    "  Widget _body(AppState state, SettingsState settings, HiddenState hidden) {\n",
    "  Widget _body(\n    AppState state,\n    SettingsState settings,\n    HiddenState hidden,\n    SortedState sorted,\n  ) {\n",
    'home body signature',
)

home = replace_once(
    home,
    "    if (state.loading && state.listings.isEmpty) {\n      return const Center(child: CircularProgressIndicator());\n    }\n",
    "",
    'duplicate initial loader',
)

home = replace_once(
    home,
    "      hidden,\n    );\n\n    if (listings.isEmpty) {\n",
    "      hidden,\n      sorted,\n    );\n\n    if (listings.isEmpty) {\n",
    'sorted argument into applyTab',
)

map_block = re.compile(
    r"    if \(listings\.isEmpty\) \{\n"
    r"      return Center\(child: Text\(_emptyLabel\(settings\)\)\);\n"
    r"    \}\n\n"
    r"    if \(_mapMode\) \{.*?"
    r"\n    \}\n"
    r"    return RefreshIndicator\(",
    re.S,
)
new_map_block = """    if (_mapMode) {
      final mapCountry = state.filters.countries.isNotEmpty
          ? state.filters.countries.first
          : '';
      final mapItems = _applyTab(
        state.mapListings.isNotEmpty ? state.mapListings : listings,
        hidden,
        sorted,
      );
      final focusKey = _focusListing == null
          ? 'browse'
          : '${_focusListing!.source}:${_focusListing!.id}';
      return Stack(
        children: [
          Positioned.fill(
            child: MapView(
              // Include explicit listing focus in the key. A card-to-map jump
              // must not be reused as an ordinary browse camera instance.
              key: ValueKey(
                'map-$mapCountry-${state.filters.city}-$focusKey',
              ),
              listings: mapItems,
              center: center,
              centerZoom: _focusListing?.hasLocation == true ? 18 : 6,
              onTapListing: _showMapPreview,
              rates: state.rates,
              displayCurrency: settings.displayCurrency,
              country: mapCountry,
              city: state.filters.city,
              locale: settings.lang,
              radiusCenter: state.filters.centerLat != null &&
                      state.filters.centerLng != null
                  ? LatLng(
                      state.filters.centerLat!.toDouble(),
                      state.filters.centerLng!.toDouble(),
                    )
                  : null,
              radiusM: state.filters.radiusM?.toDouble(),
              onRadiusCenterChanged: (point) => _setRadiusCenter(state, point),
              onRadiusChanged: (radius) => _setRadius(state, radius),
              onExpand: () => _openFullScreenMap(
                state,
                settings,
                mapCountry,
                mapItems,
                center,
              ),
            ),
          ),
          // Keep the map and its geography controls usable when the current
          // filters return nothing. The empty state is only a floating notice.
          if (mapItems.isEmpty && !state.loading && !state.mapLoading)
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: IgnorePointer(
                child: Center(
                  child: Card(
                    elevation: 6,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Text(
                        _emptyLabel(settings),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    if (listings.isEmpty) {
      return Center(child: Text(_emptyLabel(settings)));
    }

    return RefreshIndicator("""
home, count = map_block.subn(new_map_block, home, count=1)
if count != 1:
    raise SystemExit(f'home map empty-state block: expected one match, found {count}')

inline_loader = """          if (state.loading) ...[
            // Blocks taps on the (still-visible, now stale) list while a
            // reload is in flight, so a tap can't land on a card that's
            // about to be replaced.
            const Positioned.fill(
              child: AbsorbPointer(child: SizedBox.expand()),
            ),
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(),
            ),
          ],
"""
home = replace_once(home, inline_loader, '', 'duplicate inline list loader')

home = replace_once(
    home,
    "  List<Listing> _applyTab(List<Listing> listings, HiddenState hidden) {\n",
    "  List<Listing> _applyTab(\n    List<Listing> listings,\n    HiddenState hidden,\n    SortedState sorted,\n  ) {\n",
    'applyTab signature',
)
home = replace_once(
    home,
    "    final active = listings.where((l) => !hidden.isHidden(l.id));\n",
    "    final active = listings.where(\n      (l) => !hidden.isHidden(l.id) && !sorted.containsListing(l),\n    );\n",
    'exclude sorted listings',
)

home_path.write_text(home, encoding='utf-8')


map_path = Path('app/lib/widgets/map_view.dart')
map_text = map_path.read_text(encoding='utf-8')

focus_pattern = '_syncSelectionFromFilters(focus: true)'
focus_count = map_text.count(focus_pattern)
if focus_count != 2:
    raise SystemExit(
        f'map filter focus guard: expected two matches, found {focus_count}'
    )
map_text = map_text.replace(
    focus_pattern,
    '_syncSelectionFromFilters(focus: !_isFocused)',
)

select_zone = re.compile(
    r"  Future<void> _selectZone\(\n.*?"
    r"\n  \}\n\n  double _ringAreaScore",
    re.S,
)
new_select_zone = """  Future<void> _selectZone(
    DistrictZone zone, {
    num? metroRadiusM,
  }) async {
    final current = context.read<AppState>().filters;
    final sameZone = _selectedZoneId == zone.id;

    // Metro uses a deliberate two-tap interaction. The first tap only selects
    // the station and reveals its label/rings. The second tap applies it as a
    // search filter. A further tap on an already-filtered station clears it.
    if (zone.type == 'metro') {
      final alreadyFiltered = current.metro == zone.name &&
          (metroRadiusM == null || current.metroMaxM == metroRadiusM);

      if (!sameZone) {
        final district = _ancestorOfType(zone, 'district');
        setState(() {
          _selectedZoneId = zone.id;
          _selectedDistrictId = district?.id;
          _activeZoneFocusId = zone.id;
          _expandedGroupKey = null;
          _showLayerFor(zone);
        });
        _focusZone(zone);
        return;
      }

      if (!alreadyFiltered) {
        await _applyZoneScope(zone, metroRadiusM: metroRadiusM);
        return;
      }

      setState(() {
        _selectedZoneId = null;
        _selectedDistrictId = null;
        _activeZoneFocusId = null;
        _expandedGroupKey = null;
      });
      await _clearZoneScope(zone);
      return;
    }

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
    await _applyZoneScope(zone, metroRadiusM: metroRadiusM);
  }

  double _ringAreaScore"""
map_text, count = select_zone.subn(new_select_zone, map_text, count=1)
if count != 1:
    raise SystemExit(f'map metro two-tap block: expected one match, found {count}')

map_path.write_text(map_text, encoding='utf-8')

print('Applied mobile map/review fixes.')

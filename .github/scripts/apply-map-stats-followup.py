from pathlib import Path


def read(path):
    return Path(path).read_text()


def write(path, text):
    Path(path).write_text(text)


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, got {count}")
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# Statistics: deal scope belongs here as compact radio controls, not as pills
# on the home screen. Keep unknown data for completeness metrics but never make
# it a selectable price-distribution scope.
# ---------------------------------------------------------------------------
path = 'app/lib/widgets/stats_sheet.dart'
text = read(path)
text = replace_once(
    text,
    """        'roomRent' => s.t('roomOnly'),
        _ => key,
""",
    """        'roomRent' => s.t('roomOnly'),
        'unknown' => s.t('notSpecified'),
        _ => key,
""",
    'localize unknown deal type',
)
text = replace_once(
    text,
    """    final scopedGeo = stats.geographiesByDeal[_dealScope]?[_geoDimension];
    final geography = (scopedGeo?.isNotEmpty == true
            ? scopedGeo!
            : stats.geographies[_geoDimension] ?? const <GeoStat>[])
        .take(8)
        .toList();
    final bands = stats.priceBandsByDeal[_dealScope] ?? const <PriceBandStat>[];
""",
    """    const knownDealScopes = {'sale', 'longRent', 'shortRent', 'roomRent'};
    final dealScopes = stats.dealTypes
        .where((row) => row.count > 0 && knownDealScopes.contains(row.key))
        .map((row) => row.key)
        .toList();
    final effectiveDealScope = dealScopes.contains(_dealScope)
        ? _dealScope
        : (dealScopes.isNotEmpty ? dealScopes.first : null);
    final scopedGeo = effectiveDealScope == null
        ? null
        : stats.geographiesByDeal[effectiveDealScope]?[_geoDimension];
    final geography = (scopedGeo?.isNotEmpty == true
            ? scopedGeo!
            : stats.geographies[_geoDimension] ?? const <GeoStat>[])
        .take(8)
        .toList();
    final bands = effectiveDealScope == null
        ? const <PriceBandStat>[]
        : stats.priceBandsByDeal[effectiveDealScope] ?? const <PriceBandStat>[];
""",
    'effective known deal scope',
)
text = text.replace('_dealSegments(stats, s)', '_dealRadios(stats, s)')
old_method = """  Widget _dealSegments(SearchStatistics stats, AppStrings s) {
    final values =
        stats.dealTypes.where((e) => e.count > 0).map((e) => e.key).toList();
    if (values.isEmpty) return const SizedBox.shrink();
    final selected = values.contains(_dealScope) ? _dealScope : values.first;
    return _segments<String>(
      values,
      selected,
      (v) => _dealLabel(s, v),
      (v) => setState(() => _dealScope = v),
    );
  }

"""
new_method = """  Widget _dealRadios(SearchStatistics stats, AppStrings s) {
    const known = {'sale', 'longRent', 'shortRent', 'roomRent'};
    final values = stats.dealTypes
        .where((e) => e.count > 0 && known.contains(e.key))
        .map((e) => e.key)
        .toList();
    if (values.isEmpty) return const SizedBox.shrink();
    final selected = values.contains(_dealScope) ? _dealScope : values.first;
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      children: [
        for (final value in values)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _dealScope = value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected == value
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: selected == value
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                  Text(_dealLabel(s, value), textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
      ],
    );
  }

"""
text = replace_once(text, old_method, new_method, 'deal radios')
write(path, text)


# ---------------------------------------------------------------------------
# Map interaction: every cluster tap centers on that cluster. Clusters > 10 do
# exactly one +1 zoom step; clusters <= 10 center without zooming and open the
# price-dot radial selector.
# ---------------------------------------------------------------------------
path = 'app/lib/widgets/map_view.dart'
text = read(path)
text = replace_once(
    text,
    """    if (group.listings.length > _radialCapacity) {
      if (_zoom < _clusterZoomMax - 0.01) {
        final targetZoom = math.min(_zoom + 1.0, _clusterZoomMax);
        setState(() => _expandedGroupKey = null);
        _controller.move(group.point, targetZoom);
      }
      return;
    }
    setState(() => _expandedGroupKey = group.key);
""",
    """    if (group.listings.length > _radialCapacity) {
      if (_zoom < _clusterZoomMax - 0.01) {
        final targetZoom = math.min(_zoom + 1.0, _clusterZoomMax);
        setState(() => _expandedGroupKey = null);
        _controller.move(group.point, targetZoom);
      } else {
        _controller.move(group.point, _zoom);
      }
      return;
    }
    _controller.move(group.point, _zoom);
    setState(() => _expandedGroupKey = group.key);
""",
    'cluster center on tap',
)
write(path, text)


# ---------------------------------------------------------------------------
# Price colors on the map: compact map points previously discarded the market
# comparison, forcing every Flutter price marker into its pink fallback. Enrich
# the final compact point set in one batch and return that comparison metadata.
# ---------------------------------------------------------------------------
path = 'backend/src/map-feed.js'
text = read(path)
text = replace_once(
    text,
    "import { searchPostgresListings } from './postgres-search.js';\n",
    """import { searchPostgresListings } from './postgres-search.js';
import { attachMarketComparisons } from './market-comparison.js';
""",
    'map market comparison import',
)
text = replace_once(
    text,
    """  return {
    count,
    points,
    truncated,
""",
    """  let enrichedPoints = points;
  if (points.length && rates) {
    try {
      enrichedPoints = await attachMarketComparisons(points, rates);
    } catch (err) {
      console.warn('[map-feed] market comparison failed:', err?.message ?? err);
    }
  }

  return {
    count,
    points: enrichedPoints,
    truncated,
""",
    'map market comparison enrichment',
)
write(path, text)

print('map/stats follow-up applied')

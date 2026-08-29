from pathlib import Path
import re


def read(path):
    return Path(path).read_text()


def write(path, text):
    Path(path).write_text(text)


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, got {count}")
    return text.replace(old, new, 1)


def regex_once(text, pattern, repl, label, flags=0):
    out, count = re.subn(pattern, lambda _m: repl, text, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, got {count}")
    return out


# ---------------------------------------------------------------------------
# Mobile quick filters: restore Deal type as a select beside seller, keep the
# compact 42px control height, and slightly relax header icon spacing (+2px).
# ---------------------------------------------------------------------------
path = 'app/lib/screens/home_screen.dart'
text = read(path)
text = replace_once(
    text,
    "minimumSize: const Size(28, 38),\n      maximumSize: const Size(28, 38),",
    "minimumSize: const Size(30, 38),\n      maximumSize: const Size(30, 38),",
    'header icon spacing',
)

pattern = r'''              Row\(\n                crossAxisAlignment: CrossAxisAlignment\.start,\n                children: \[\n                  Expanded\(\n                    child: DropdownButtonFormField<AgencyFilter>\(.*?\n              const SizedBox\(height: 5\),\n              Row\(\n                children: \[\n                  Expanded\(\n                    child: TextField\(\n                      controller: _priceMin,'''
replacement = '''              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<AgencyFilter>(
                      value: widget.filters.agency,
                      isExpanded: true,
                      isDense: true,
                      decoration: InputDecoration(
                        labelText: s.t('quickAgency'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: AgencyFilter.any,
                          child: Text(s.t('any')),
                        ),
                        DropdownMenuItem(
                          value: AgencyFilter.owner,
                          child: Text(s.t('owner')),
                        ),
                        DropdownMenuItem(
                          value: AgencyFilter.agency,
                          child: Text(s.t('agency')),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        _schedule(
                          _withTextValues().copyWith(agency: value),
                          immediate: true,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: DropdownButtonFormField<_QuickDeal>(
                      value: _quickDealFor(widget.filters),
                      isExpanded: true,
                      isDense: true,
                      decoration: InputDecoration(labelText: s.t('dealType')),
                      items: [
                        DropdownMenuItem(
                          value: _QuickDeal.any,
                          child: Text(s.t('any')),
                        ),
                        DropdownMenuItem(
                          value: _QuickDeal.sale,
                          child: Text(s.t('sale')),
                        ),
                        DropdownMenuItem(
                          value: _QuickDeal.longRent,
                          child: Text(s.t('longTerm')),
                        ),
                        DropdownMenuItem(
                          value: _QuickDeal.room,
                          child: Text(s.t('roomOnly')),
                        ),
                        DropdownMenuItem(
                          value: _QuickDeal.shortRent,
                          child: Text(s.t('shortTerm')),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        _schedule(
                          _withQuickDeal(_withTextValues(), value),
                          immediate: true,
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _priceMin,'''
text = regex_once(text, pattern, replacement, 'restore deal select', flags=re.S)
write(path, text)


# Searchable dropdown must inherit the active InputDecorationTheme constraints:
# 42px on the compact home filters, 48px in the full filter sheet.
path = 'app/lib/widgets/searchable_dropdown.dart'
text = read(path)
text = replace_once(
    text,
    "          constraints: const BoxConstraints(minHeight: 42),\n",
    "",
    'searchable dropdown inherited height',
)
write(path, text)


# ---------------------------------------------------------------------------
# Geography labels: include actual listing cities/districts for every country,
# not only Ukraine, so canonical lexicon display names such as Urgench and
# Yangihayot reach Flutter's city/district label maps.
# ---------------------------------------------------------------------------
path = 'backend/src/catalog-routes.js'
text = read(path)
old = '''          if (code === 'UA') {
            try {
              const rows = await getAvailableListingLocations(code);

              for (const row of rows) {
                const city = canonicalCityName(code, row.city);
                if (!city) continue;

                cities.add(city);
                if (!locations[city]) {
                  locations[city] = {districts: [], metro: []};
                }

                const district = String(row.district ?? '').trim();
                if (district && !locations[city].districts.includes(district)) {
                  locations[city].districts.push(district);
                }
              }
            } catch (err) {
              console.warn(
                `[locations] ${code} dynamic locations failed: ${err?.message ?? err}`,
              );
            }
          }
'''
new = '''          try {
            const rows = await getAvailableListingLocations(code);

            for (const row of rows) {
              const city = canonicalCityName(code, row.city);
              if (!city) continue;

              cities.add(city);
              if (!locations[city]) {
                locations[city] = {districts: [], metro: []};
              }

              const district = String(row.district ?? '').trim();
              if (district && !locations[city].districts.includes(district)) {
                locations[city].districts.push(district);
              }
            }
          } catch (err) {
            console.warn(
              `[locations] ${code} dynamic locations failed: ${err?.message ?? err}`,
            );
          }
'''
text = replace_once(text, old, new, 'dynamic geography for all countries')
write(path, text)

# If a source attaches a canonical district to a neighboring/incorrect city,
# display can still reuse the same localized canonical label from another city
# map without changing the filter value or geography identity.
path = 'app/lib/models/filters.dart'
text = read(path)
text = replace_once(
    text,
    """  String locationLabel(String city, String value, {String? kind}) =>
      locations[city]?.labelFor(value, kind: kind) ?? value;
""",
    """  String locationLabel(String city, String value, {String? kind}) {
    final direct = locations[city]?.labelFor(value, kind: kind);
    if (direct != null && direct != value) return direct;
    return locationLabelAnyCity(value, kind: kind);
  }
""",
    'location display fallback',
)
write(path, text)


# ---------------------------------------------------------------------------
# Map clusters: one user tap means exactly one zoom step. Never auto-zoom all
# the way to radial capacity. A radial price wheel opens only once the tapped
# cluster itself contains <= 10 listings.
# ---------------------------------------------------------------------------
path = 'app/lib/widgets/map_view.dart'
text = read(path)
text = regex_once(
    text,
    r'''\n  bool _hasRealSpread\(_PinGroup group\) \{.*?\n  \}\n\n  double _zoomForRadialCapacity\(_PinGroup group\) \{.*?\n  \}\n''',
    '\n',
    'remove auto radial zoom helpers',
    flags=re.S,
)
text = replace_once(
    text,
    '''    if (group.listings.length > _radialCapacity &&
        _hasRealSpread(group) &&
        _zoom < _clusterZoomMax - 0.01) {
      final targetZoom = _zoomForRadialCapacity(group);
      setState(() => _expandedGroupKey = null);
      _controller.move(group.point, targetZoom);
      return;
    }
    setState(() => _expandedGroupKey = group.key);
''',
    '''    if (group.listings.length > _radialCapacity) {
      if (_zoom < _clusterZoomMax - 0.01) {
        final targetZoom = math.min(_zoom + 1.0, _clusterZoomMax);
        setState(() => _expandedGroupKey = null);
        _controller.move(group.point, targetZoom);
      }
      return;
    }
    setState(() => _expandedGroupKey = group.key);
''',
    'single-step cluster zoom',
)
write(path, text)


# ---------------------------------------------------------------------------
# Pills that remain in statistics are visually centered, including multi-line
# labels. Main-page transaction pills are intentionally gone (select restored).
# ---------------------------------------------------------------------------
path = 'app/lib/widgets/stats_sheet.dart'
text = read(path)
text = text.replace("label: Text('$days'),", "label: Text('$days', textAlign: TextAlign.center),")
text = text.replace("label: Text(label(v))", "label: Text(label(v), textAlign: TextAlign.center)")
write(path, text)

print('UI follow-up patch applied')

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
    out, count = re.subn(pattern, repl, text, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, got {count}")
    return out


# ---------------------------------------------------------------------------
# Backend: use parsing-lexicon as the only vocabulary source for display
# labels. geographyDisplayName handles its explicit display tables; the
# canonical LOCATION_DICTIONARIES aliases fill the currently unsupported
# mahalla/local-area and wider city-local coverage without copying vocabulary
# into Flat Finder.
# ---------------------------------------------------------------------------
path = "backend/src/catalog-routes.js"
text = read(path)
text = replace_once(
    text,
    "import {geographyDisplayName} from '@whiteslove/parsing-lexicon/geography-display';\n",
    "import {geographyDisplayName} from '@whiteslove/parsing-lexicon/geography-display';\nimport {dictionaryFor} from '@whiteslove/parsing-lexicon/locations';\n",
    "catalog lexicon locations import",
)
text = regex_once(
    text,
    r"/\*\* \{raw name -> localized label\}, only for names that actually translate\. \*/\nfunction labelMap\(names, locale, kind\) \{.*?\n\}\n",
    r'''/**
 * Presentation adapter over parsing-lexicon's canonical location aliases.
 * No geography vocabulary is owned here: raw values stay canonical for API
 * filtering, while clients receive a parallel raw -> localized label map.
 */
const LOCATION_KIND_KEYS = Object.freeze({
  district: ['districts'],
  microdistrict: ['microdistricts'],
  metro: ['metro'],
  mahalla: ['mahallas'],
  local_area: ['localAreas', 'developmentAreas'],
});

const CYRILLIC_RE = /\p{Script=Cyrillic}/u;
// Prefer Russian-script aliases over Ukrainian/Uzbek/Kazakh Cyrillic when a
// canonical entry contains several Cyrillic language variants.
const NON_RUSSIAN_CYRILLIC_RE = /[ІіЇїЄєҐґЎўҚқҒғҲҳӘәӨөҰұҮүҢң]/u;

function preferredLexiconAlias(entry, locale) {
  const language = String(locale || 'en').toLowerCase().split(/[-_]/)[0];
  if (language !== 'ru') return entry?.canonical || entry?.name || null;
  const aliases = (entry?.aliases || []).map((value) => String(value).trim()).filter(Boolean);
  return aliases.find((alias) => CYRILLIC_RE.test(alias) && !NON_RUSSIAN_CYRILLIC_RE.test(alias))
    || aliases.find((alias) => CYRILLIC_RE.test(alias))
    || entry?.canonical
    || entry?.name
    || null;
}

function lexiconLocationLabel(name, locale, kind, countryCode, cityName) {
  const raw = String(name || '').trim();
  if (!raw) return '';

  // Keep the package's curated display tables first where they exist.
  if (kind === 'district' || kind === 'microdistrict' || kind === 'metro') {
    const direct = geographyDisplayName(raw, locale, kind);
    if (direct && direct !== raw) return direct;
  }

  const dictionary = dictionaryFor(countryCode, cityName);
  const keys = LOCATION_KIND_KEYS[kind] || [];
  for (const key of keys) {
    const entry = (dictionary?.[key] || []).find((candidate) =>
      candidate?.canonical === raw
      || candidate?.name === raw
      || candidate?.aliases?.includes(raw));
    if (!entry) continue;
    return preferredLexiconAlias(entry, locale) || raw;
  }
  return raw;
}

/** {raw name -> localized label}, only for names that actually translate. */
function labelMap(names, locale, kind, countryCode = '', cityName = '') {
  const map = {};
  for (const name of names) {
    const label = LOCATION_KIND_KEYS[kind]
      ? lexiconLocationLabel(name, locale, kind, countryCode, cityName)
      : geographyDisplayName(name, locale, kind);
    if (label && label !== name) map[name] = label;
  }
  return map;
}

function localizedMapZones(zones, locale, countryCode, cityName) {
  if (!locale) return zones;
  const mapGroup = (items, kind) => items.map((zone) => ({
    ...zone,
    label: lexiconLocationLabel(zone.name, locale, kind, countryCode, cityName),
  }));
  return {
    ...zones,
    districtZones: mapGroup(zones.districtZones || [], 'district'),
    microdistrictMarkers: mapGroup(zones.microdistrictMarkers || [], 'microdistrict'),
    quartalMarkers: mapGroup(zones.quartalMarkers || [], 'mahalla'),
    areaZones: mapGroup(zones.areaZones || [], 'local_area'),
    cityZone: zones.cityZone
      ? {...zones.cityZone, label: geographyDisplayName(zones.cityZone.name, locale, 'city')}
      : null,
  };
}
''',
    "catalog label helpers",
    flags=re.S,
)
text = text.replace(
    "location.districtLabels = labelMap(location.districts, locale, 'district');",
    "location.districtLabels = labelMap(location.districts, locale, 'district', code, cityName);",
)
text = text.replace(
    "location.metroLabels = labelMap(location.metro, locale, 'metro');",
    "location.metroLabels = labelMap(location.metro, locale, 'metro', code, cityName);",
)
text = text.replace(
    "location.microdistrictLabels = labelMap(location.microdistricts, locale, 'any');",
    "location.microdistrictLabels = labelMap(location.microdistricts, locale, 'microdistrict', code, cityName);",
)
text = text.replace(
    "location.quartalLabels = labelMap(location.quartals, locale, 'any');",
    "location.quartalLabels = labelMap(location.quartals, locale, 'mahalla', code, cityName);",
)
text = text.replace(
    "location.areaLabels = labelMap(location.areas, locale, 'any');",
    "location.areaLabels = labelMap(location.areas, locale, 'local_area', code, cityName);",
)
text = replace_once(
    text,
    """      const locations = cityLocations(country);\n      const districtOptions = locations[city]?.districts ?? [];\n      return res.json(mapZonesFor(country, city, districtOptions));""",
    """      const locale = String(req.query.locale || '').trim();\n      const locations = cityLocations(country);\n      const districtOptions = locations[city]?.districts ?? [];\n      const zones = mapZonesFor(country, city, districtOptions);\n      return res.json(localizedMapZones(zones, locale, country, city));""",
    "district zones locale",
)
write(path, text)


# ---------------------------------------------------------------------------
# Flutter geography models: central lookup API over backend-provided lexicon
# maps so every view uses the same display value while keeping raw canonical
# values for filters and requests.
# ---------------------------------------------------------------------------
path = "app/lib/models/filters.dart"
text = read(path)
text = replace_once(
    text,
    """    areaLabels: _stringMap(j['areaLabels']),\n  );\n}\n\nclass Country {""",
    """    areaLabels: _stringMap(j['areaLabels']),\n  );\n\n  String labelFor(String value, {String? kind}) {\n    final typed = switch (kind) {\n      'district' => districtLabels[value],\n      'metro' => metroLabels[value],\n      'microdistrict' => microdistrictLabels[value],\n      'quartal' || 'mahalla' => quartalLabels[value],\n      'area' || 'local_area' => areaLabels[value],\n      _ => null,\n    };\n    if (typed != null && typed.isNotEmpty) return typed;\n    for (final labels in [\n      districtLabels,\n      microdistrictLabels,\n      quartalLabels,\n      areaLabels,\n      metroLabels,\n    ]) {\n      final label = labels[value];\n      if (label != null && label.isNotEmpty) return label;\n    }\n    return value;\n  }\n}\n\nclass Country {""",
    "city location label helper",
)
text = replace_once(
    text,
    """  String cityLabel(String city) => cityLabels[city] ?? city;\n\n  factory Country.fromJson""",
    """  String cityLabel(String city) => cityLabels[city] ?? city;\n\n  String locationLabel(String city, String value, {String? kind}) =>\n      locations[city]?.labelFor(value, kind: kind) ?? value;\n\n  String locationLabelAnyCity(String value, {String? kind}) {\n    for (final location in locations.values) {\n      final label = location.labelFor(value, kind: kind);\n      if (label != value) return label;\n    }\n    return value;\n  }\n\n  factory Country.fromJson""",
    "country location label helpers",
)
write(path, text)


path = "app/lib/models/district_zone.dart"
text = read(path)
text = replace_once(
    text,
    """  final String name;\n  final double lat;""",
    """  final String name;\n  final String label;\n  final double lat;""",
    "zone label field",
)
text = replace_once(
    text,
    """    required this.name,\n    required this.lat,""",
    """    required this.name,\n    required this.label,\n    required this.lat,""",
    "zone label constructor",
)
text = replace_once(
    text,
    """    name: j['name']?.toString() ?? '',\n    lat:""",
    """    name: j['name']?.toString() ?? '',\n    label: j['label']?.toString() ?? j['name']?.toString() ?? '',\n    lat:""",
    "zone label json",
)
write(path, text)


path = "app/lib/services/api_service.dart"
text = read(path)
text = replace_once(
    text,
    """  Future<MapZones> fetchMapZones(String country, String city) async {\n    if (country.isEmpty || city.isEmpty) return const MapZones();\n    final uri = Uri.parse('$baseUrl/api/district-zones')\n        .replace(queryParameters: {'country': country, 'city': city});""",
    """  Future<MapZones> fetchMapZones(\n    String country,\n    String city, {\n    String locale = '',\n  }) async {\n    if (country.isEmpty || city.isEmpty) return const MapZones();\n    final uri = Uri.parse('$baseUrl/api/district-zones').replace(\n      queryParameters: {\n        'country': country,\n        'city': city,\n        if (locale.isNotEmpty) 'locale': locale,\n      },\n    );""",
    "api map zone locale",
)
write(path, text)


# ---------------------------------------------------------------------------
# Map labels: request localized zone names, render label, preserve canonical
# name/id for behavior.
# ---------------------------------------------------------------------------
path = "app/lib/widgets/map_view.dart"
text = read(path)
text = replace_once(
    text,
    """    this.country = '',\n    this.city = '',\n    this.centerZoom = 6,""",
    """    this.country = '',\n    this.city = '',\n    this.locale = '',\n    this.centerZoom = 6,""",
    "map locale constructor",
)
text = replace_once(
    text,
    """  final String country;\n  final String city;\n\n  /// Shows""",
    """  final String country;\n  final String city;\n  final String locale;\n\n  /// Shows""",
    "map locale field",
)
text = replace_once(
    text,
    """    final zones = await _api.fetchMapZones(widget.country, widget.city);""",
    """    final zones = await _api.fetchMapZones(\n      widget.country,\n      widget.city,\n      locale: widget.locale,\n    );""",
    "map locale request",
)
text = replace_once(
    text,
    """    final geographyChanged =\n        old.country != widget.country || old.city != widget.city;""",
    """    final geographyChanged =\n        old.country != widget.country ||\n        old.city != widget.city ||\n        old.locale != widget.locale;""",
    "map locale update",
)
text = text.replace("                              zone.name,", "                              zone.label,")
text = text.replace("onTap: () => _showZoneName(zone.name),", "onTap: () => _showZoneName(zone.label),")
write(path, text)


# ---------------------------------------------------------------------------
# Listing cards: city, district and metro display all flow through the country
# metadata generated from parsing-lexicon.
# ---------------------------------------------------------------------------
path = "app/lib/widgets/listing_card.dart"
text = read(path)
text = replace_once(
    text,
    """    final mobile = !grid && MediaQuery.sizeOf(context).width < 700;\n\n    final dealTone""",
    """    final mobile = !grid && MediaQuery.sizeOf(context).width < 700;\n    final geographyCountry = appState.countryByCode(listing.country);\n\n    final dealTone""",
    "listing card country",
)
text = text.replace(
    """                          actions: actions,\n                          compact: true,""",
    """                          actions: actions,\n                          geographyCountry: geographyCountry,\n                          compact: true,""",
    1,
)
text = text.replace(
    """                    actions: actions,\n                    compact: grid,""",
    """                    actions: actions,\n                    geographyCountry: geographyCountry,\n                    compact: grid,""",
    1,
)
text = replace_once(
    text,
    """    required PriceTone priceState,\n    required Widget actions,\n    bool compact = false,\n  }) {\n    final badges = _contextBadges(filters, s);\n    final location = _locationLabel(s);""",
    """    required PriceTone priceState,\n    required Widget actions,\n    required Country? geographyCountry,\n    bool compact = false,\n  }) {\n    final badges = _contextBadges(filters, s, geographyCountry);\n    final location = _locationLabel(geographyCountry);""",
    "listing card meta geography",
)
text = regex_once(
    text,
    r"  String _locationLabel\(AppStrings s\) \{.*?\n  \}\n\n  List<String> _contextBadges\(Filters filters, AppStrings s\) \{",
    r'''  String _locationLabel(Country? country) {
    final parts = <String>[];
    final city = listing.city.trim();
    if (city.isNotEmpty) parts.add(country?.cityLabel(city) ?? city);
    final district = listing.district?.trim();
    if (district != null && district.isNotEmpty) {
      parts.add(country?.locationLabel(city, district, kind: 'district') ?? district);
    }
    return parts.isEmpty ? '—' : parts.join(', ');
  }

  List<String> _contextBadges(
    Filters filters,
    AppStrings s,
    Country? country,
  ) {''',
    "listing card location methods",
    flags=re.S,
)
text = replace_once(
    text,
    """      if (district != null && district.isNotEmpty) {\n        add(district);\n      } else if (metro != null && metro.isNotEmpty) {\n        add(metro);""",
    """      if (district != null && district.isNotEmpty) {\n        add(country?.locationLabel(listing.city, district, kind: 'district') ?? district);\n      } else if (metro != null && metro.isNotEmpty) {\n        add(country?.locationLabel(listing.city, metro, kind: 'metro') ?? metro);""",
    "listing card badge location",
)
write(path, text)


# ---------------------------------------------------------------------------
# Detail/share: title, spec table, and shared parsed-location line use the same
# country metadata.
# ---------------------------------------------------------------------------
path = "app/lib/screens/listing_detail.dart"
text = read(path)
text = replace_once(
    text,
    """    final rates = context.watch<AppState>().rates;\n    final favorites""",
    """    final appState = context.watch<AppState>();\n    final rates = appState.rates;\n    final country = appState.countryByCode(listing.country);\n    final favorites""",
    "detail app state country",
)
text = replace_once(
    text,
    """        title: _DetailTitle(listing: listing, rates: rates, s: s),""",
    """        title: _DetailTitle(\n          listing: listing,\n          rates: rates,\n          s: s,\n          country: country,\n        ),""",
    "detail localized title call",
)
text = replace_once(
    text,
    """                          country: context.watch<AppState>().countryByCode(\n                            listing.country,\n                          ),""",
    """                          country: country,""",
    "detail country reuse",
)
text = replace_once(
    text,
    """  ) {\n    final b = StringBuffer()\n      ..writeln(listing.title)""",
    """  ) {\n    final country = context.read<AppState>().countryByCode(listing.country);\n    final b = StringBuffer()\n      ..writeln(listing.title)""",
    "detail share country",
)
text = replace_once(
    text,
    """    if (listing.city.isNotEmpty) info.add(listing.city);\n    if (listing.district != null) info.add(listing.district!);""",
    """    if (listing.city.isNotEmpty) {\n      info.add(country?.cityLabel(listing.city) ?? listing.city);\n    }\n    if (listing.district != null) {\n      info.add(\n        country?.locationLabel(\n              listing.city,\n              listing.district!,\n              kind: 'district',\n            ) ??\n            listing.district!,\n      );\n    }""",
    "detail share localized location",
)
text = replace_once(
    text,
    """    required this.s,\n  });\n\n  final Listing listing;\n  final Map<String, double> rates;\n  final AppStrings s;""",
    """    required this.s,\n    this.country,\n  });\n\n  final Listing listing;\n  final Map<String, double> rates;\n  final AppStrings s;\n  final Country? country;""",
    "detail title country field",
)
text = replace_once(
    text,
    """      return Text('${countryFlags[listing.country] ?? ''} ${listing.city}');""",
    """      final city = country?.cityLabel(listing.city) ?? listing.city;\n      return Text('${countryFlags[listing.country] ?? ''} $city');""",
    "detail no public id city",
)
text = replace_once(
    text,
    """      listing.city,\n    ].where((e) => e.isNotEmpty).join(', ');""",
    """      country?.cityLabel(listing.city) ?? listing.city,\n    ].where((e) => e.isNotEmpty).join(', ');""",
    "detail title city",
)
text = replace_once(
    text,
    """        l.city.isNotEmpty\n            ? (country?.cityLabel(l.city) ?? cityLabel(l.city, s.lang))\n            : null,""",
    """        l.city.isNotEmpty ? (country?.cityLabel(l.city) ?? l.city) : null,""",
    "detail spec city",
)
text = replace_once(
    text,
    """        l.district == null ? null : (_cityLoc?.districtLabels[l.district] ?? l.district),""",
    """        l.district == null\n            ? null\n            : (country?.locationLabel(l.city, l.district!, kind: 'district') ??\n                  l.district),""",
    "detail spec district",
)
text = replace_once(
    text,
    """        l.kvartal == null ? null : (_cityLoc?.quartalLabels[l.kvartal] ?? l.kvartal),""",
    """        l.kvartal == null\n            ? null\n            : (country?.locationLabel(l.city, l.kvartal!, kind: 'quartal') ??\n                  l.kvartal),""",
    "detail spec quartal",
)
text = replace_once(
    text,
    """        l.metro == null ? null : (_cityLoc?.metroLabels[l.metro] ?? l.metro),""",
    """        l.metro == null\n            ? null\n            : (country?.locationLabel(l.city, l.metro!, kind: 'metro') ??\n                  l.metro),""",
    "detail spec metro",
)
# _cityLoc is no longer needed after routing every location field through Country.
text = text.replace("\n  CityLocations? get _cityLoc => country?.locations[listing.city];\n", "\n")
write(path, text)


# ---------------------------------------------------------------------------
# Statistics: localize raw aggregation labels through the same Country maps.
# ---------------------------------------------------------------------------
path = "app/lib/widgets/stats_sheet.dart"
text = read(path)
text = replace_once(
    text,
    "import '../services/api_service.dart';\nimport '../state/settings.dart';",
    "import '../services/api_service.dart';\nimport '../state/app_state.dart';\nimport '../state/settings.dart';",
    "stats app state import",
)
insert = r'''
  String _localizedGeographyLabel(
    AppState state,
    AppStrings s,
    String dimension,
    String raw,
  ) {
    if (dimension == 'country') return s.countryName(raw, raw);
    final code = widget.filters.countries.isNotEmpty
        ? widget.filters.countries.first
        : '';
    final country = state.countryByCode(code);
    if (country == null) return raw;
    if (dimension == 'city') return country.cityLabel(raw);
    final city = widget.filters.city.trim();
    if (city.isNotEmpty) {
      return country.locationLabel(city, raw, kind: dimension);
    }
    return country.locationLabelAnyCity(raw, kind: dimension);
  }
'''
text = replace_once(
    text,
    """  String _geoLabel(AppStrings s, String key) => switch (key) {\n    'country' => s.t('country'),\n    'city' => s.t('city'),\n    'district' => s.t('district'),\n    'microdistrict' => s.t('microdistrict'),\n    'metro' => s.t('metro'),\n    _ => key,\n  };\n""",
    """  String _geoLabel(AppStrings s, String key) => switch (key) {\n    'country' => s.t('country'),\n    'city' => s.t('city'),\n    'district' => s.t('district'),\n    'microdistrict' => s.t('microdistrict'),\n    'metro' => s.t('metro'),\n    _ => key,\n  };\n""" + insert,
    "stats geo helper",
)
text = replace_once(
    text,
    """    final s = settings.s;\n    final number""",
    """    final s = settings.s;\n    final appState = context.watch<AppState>();\n    final number""",
    "stats state",
)
text = regex_once(
    text,
    r"                      // The backend returns raw geography names; only city\n                      // names have a \(partial, RO/KZ/UZ\) local translation\n                      // dict client-side, matching the listing cards\.\n                      _geoDimension == 'city'\n                          \? cityLabel\(row\.label, s\.lang\)\n                          : row\.label,",
    "                      _localizedGeographyLabel(appState, s, _geoDimension, row.label),",
    "stats geo row",
)
write(path, text)


# ---------------------------------------------------------------------------
# Remove the obsolete client-maintained city translation dictionary. All
# visible geography now comes from backend lexicon label maps.
# ---------------------------------------------------------------------------
path = "app/lib/utils/format.dart"
text = read(path)
text = regex_once(
    text,
    r"/// Russian names for the backend's Romania/Kazakhstan/Uzbekistan city lists.*?String cityLabel\(String city, String locale\) \{\n  if \(!locale\.toLowerCase\(\)\.startsWith\('ru'\)\) return city;\n  return _cityNamesRu\[city\] \?\? city;\n\}\n\n",
    """/// Geography display labels are supplied by /api/countries from\n/// @whiteslove/parsing-lexicon. This compatibility helper deliberately does\n/// not own a second city dictionary; UI code should prefer Country.cityLabel.\n@Deprecated('Use Country.cityLabel from localized country metadata')\nString cityLabel(String city, String locale) => city;\n\n""",
    "remove local city dictionary",
    flags=re.S,
)
write(path, text)


# ---------------------------------------------------------------------------
# Home: pass locale into map zone requests and compact the app header. 48px
# default Material action slots become 32px (one-third narrower); toolbar 46 -> 40.
# ---------------------------------------------------------------------------
path = "app/lib/screens/home_screen.dart"
text = read(path)
text = replace_once(
    text,
    """    final hidden = context.watch<HiddenState>();\n    // Cheap no-op""",
    """    final hidden = context.watch<HiddenState>();\n    final headerActionStyle = IconButton.styleFrom(\n      minimumSize: const Size(32, 40),\n      maximumSize: const Size(32, 40),\n      padding: EdgeInsets.zero,\n      tapTargetSize: MaterialTapTargetSize.shrinkWrap,\n    );\n    // Cheap no-op""",
    "header style",
)
text = text.replace("toolbarHeight: 46,", "toolbarHeight: 40,", 1)
text = text.replace(
    "actionsPadding: const EdgeInsets.symmetric(horizontal: 1),",
    "actionsPadding: EdgeInsets.zero,",
    1,
)
# Add style to the two IconButtons and three PopupMenuButtons in the main app bar.
text = text.replace(
    """            constraints: const BoxConstraints(),\n            icon: Icon(_mapMode ? Icons.view_list : Icons.map_outlined),""",
    """            style: headerActionStyle,\n            icon: Icon(_mapMode ? Icons.view_list : Icons.map_outlined),""",
    1,
)
text = text.replace(
    """            padding: const EdgeInsets.symmetric(horizontal: 1),\n            icon: Icon(\n              Icons.sort,""",
    """            padding: EdgeInsets.zero,\n            style: headerActionStyle,\n            icon: Icon(\n              Icons.sort,""",
    1,
)
text = text.replace(
    """            padding: const EdgeInsets.symmetric(horizontal: 1),\n            icon: Icon(\n              Icons.currency_exchange,""",
    """            padding: EdgeInsets.zero,\n            style: headerActionStyle,\n            icon: Icon(\n              Icons.currency_exchange,""",
    1,
)
text = text.replace(
    """            constraints: const BoxConstraints(),\n            icon: const Icon(Icons.bar_chart_outlined),""",
    """            style: headerActionStyle,\n            icon: const Icon(Icons.bar_chart_outlined),""",
    1,
)
text = replace_once(
    text,
    """            padding: const EdgeInsets.symmetric(horizontal: 1),\n            icon: const Icon(Icons.more_vert, size: 20),""",
    """            padding: EdgeInsets.zero,\n            style: headerActionStyle,\n            icon: const Icon(Icons.more_vert, size: 20),""",
    "header more style",
)
# Existing IconButtons also have a 1px padding line; remove only the first two
# remaining main-header occurrences now that style owns their slot.
text = text.replace("padding: const EdgeInsets.symmetric(horizontal: 1),\n            style: headerActionStyle,", "padding: EdgeInsets.zero,\n            style: headerActionStyle,")
text = replace_once(
    text,
    """            country: country,\n            city: state.filters.city,\n          ),""",
    """            country: country,\n            city: state.filters.city,\n            locale: settings.lang,\n          ),""",
    "fullscreen map locale",
)
text = replace_once(
    text,
    """        country: mapCountry,\n        city: state.filters.city,\n        onExpand:""",
    """        country: mapCountry,\n        city: state.filters.city,\n        locale: settings.lang,\n        onExpand:""",
    "inline map locale",
)
write(path, text)

print('Location localization + header patch applied')

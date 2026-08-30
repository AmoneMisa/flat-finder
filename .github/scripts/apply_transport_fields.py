from pathlib import Path
import json

root = Path('.')
geo_spec = 'https://codeload.github.com/AmoneMisa/geo-catalog/tar.gz/2d83deeaf0d1c199f5465df9210d9c2cc2fd781a'

package_path = root / 'backend/package.json'
package = json.loads(package_path.read_text())
package['dependencies']['@whiteslove/geo-catalog'] = geo_spec
package_path.write_text(json.dumps(package, indent=2) + '\n')

listing_path = root / 'app/lib/models/listing.dart'
text = listing_path.read_text()

transport_class = r'''
class NearbyTransportStop {
  final String id;
  final String name;
  final String mode;
  final int distanceM;
  final List<String> routeRefs;

  const NearbyTransportStop({
    required this.id,
    required this.name,
    required this.mode,
    required this.distanceM,
    this.routeRefs = const [],
  });

  factory NearbyTransportStop.fromJson(Map<String, dynamic> j) => NearbyTransportStop(
    id: j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    mode: j['mode']?.toString() ?? '',
    distanceM: (j['distanceM'] as num?)?.round() ?? 0,
    routeRefs: (j['routeRefs'] as List?)?.map((e) => e.toString()).toList() ?? const [],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'mode': mode,
    'distanceM': distanceM,
    'routeRefs': routeRefs,
  };

  String get displayLabel {
    final routes = routeRefs.isEmpty ? '' : ' · ${routeRefs.join(', ')}';
    return '$name$routes · $distanceM m';
  }
}
'''
marker = '\nString? _locationName(dynamic value) {'
if 'class NearbyTransportStop {' not in text:
    assert marker in text
    text = text.replace(marker, '\n' + transport_class + marker, 1)

old = "  final String? metro; // nearest metro/transit station | null\n  final List<String> nearby; // nearby landmarks"
new = "  final String? metro; // nearest metro/transit station | null\n  final List<NearbyTransportStop> nearbyMetro;\n  final List<NearbyTransportStop> nearbyTransport;\n  final List<String> nearby; // nearby landmarks"
if old in text:
    text = text.replace(old, new, 1)

old = "    required this.metro,\n    required this.nearby,"
new = "    required this.metro,\n    this.nearbyMetro = const [],\n    this.nearbyTransport = const [],\n    required this.nearby,"
if old in text:
    text = text.replace(old, new, 1)

old = "  bool get hasLocation => lat != null && lng != null;\n"
new = r'''  bool get hasLocation => lat != null && lng != null;

  List<NearbyTransportStop> transportByMode(String mode) => nearbyTransport
      .where((stop) => stop.mode == mode)
      .toList(growable: false);

  String? transportSummary(String mode) {
    final stops = transportByMode(mode);
    if (stops.isEmpty) return null;
    return stops.map((stop) => stop.displayLabel).join(', ');
  }
'''
if old in text and 'transportSummary(String mode)' not in text:
    text = text.replace(old, new, 1)

old = "      metro: _locationName(j['metro']),\n      nearby:\n"
new = r'''      metro: _locationName(j['metro']),
      nearbyMetro: (j['nearbyMetro'] as List?)
              ?.whereType<Map>()
              .map((e) => NearbyTransportStop.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      nearbyTransport: (j['nearbyTransport'] as List?)
              ?.whereType<Map>()
              .map((e) => NearbyTransportStop.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      nearby:
'''
if old in text:
    text = text.replace(old, new, 1)

old = "    'metro': metro,\n    'nearby': nearby,"
new = "    'metro': metro,\n    'nearbyMetro': nearbyMetro.map((e) => e.toJson()).toList(),\n    'nearbyTransport': nearbyTransport.map((e) => e.toJson()).toList(),\n    'nearby': nearby,"
if old in text:
    text = text.replace(old, new, 1)

assert 'final List<NearbyTransportStop> nearbyTransport;' in text
assert 'transportSummary(String mode)' in text
listing_path.write_text(text)

detail_path = root / 'app/lib/screens/listing_detail.dart'
text = detail_path.read_text()
needle = r'''      (
        Icons.directions_subway_outlined,
        'metro',
        l.metro == null
            ? null
            : (country?.locationLabel(l.city, l.metro!, kind: 'metro') ??
                  l.metro),
      ),
      (Icons.location_on_outlined, 'address', l.address),'''
replacement = r'''      (
        Icons.directions_subway_outlined,
        'metro',
        l.metro == null
            ? null
            : (country?.locationLabel(l.city, l.metro!, kind: 'metro') ??
                  l.metro),
      ),
      (Icons.tram_outlined, 'tram', l.transportSummary('tram')),
      (Icons.directions_bus_outlined, 'bus', l.transportSummary('bus')),
      (Icons.electric_rickshaw_outlined, 'trolleybus', l.transportSummary('trolleybus')),
      (Icons.location_on_outlined, 'address', l.address),'''
if "l.transportSummary('tram')" not in text:
    assert needle in text, 'metro location rows marker not found'
    text = text.replace(needle, replacement, 1)
detail_path.write_text(text)

strings_path = root / 'app/lib/l10n/strings.dart'
text = strings_path.read_text()
if "'specTram': 'Tram'" not in text:
    text = text.replace("      'specMetro': 'Metro',\n", "      'specMetro': 'Metro',\n      'specTram': 'Tram',\n      'specBus': 'Bus',\n      'specTrolleybus': 'Trolleybus',\n", 1)
if "'specTram': 'Трамвай'" not in text:
    text = text.replace("      'specMetro': 'Метро',\n", "      'specMetro': 'Метро',\n      'specTram': 'Трамвай',\n      'specBus': 'Автобус',\n      'specTrolleybus': 'Троллейбус',\n", 1)
assert "'specTram': 'Tram'" in text and "'specTram': 'Трамвай'" in text
strings_path.write_text(text)

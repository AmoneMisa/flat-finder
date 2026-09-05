from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    if new in text:
        return
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{path}: expected one replacement target, found {count}')
    file.write_text(text.replace(old, new, 1), encoding='utf-8')


listing = 'app/lib/models/listing.dart'

replace_once(
    listing,
    """  final int distanceM;\n  final List<String> routeRefs;\n  final String? geoEntityId;\n""",
    """  final int distanceM;\n  final int? walkingDistanceM;\n  final int? walkingDurationMin;\n  final List<String> routeRefs;\n  final String? geoEntityId;\n""",
)

replace_once(
    listing,
    """  final Map<String, dynamic>? osm;\n  final String? source;\n\n  const NearbyTransportStop({\n""",
    """  final Map<String, dynamic>? osm;\n  final String? source;\n  final String? walkingSource;\n\n  const NearbyTransportStop({\n""",
)

replace_once(
    listing,
    """    required this.mode,\n    required this.distanceM,\n    this.routeRefs = const [],\n""",
    """    required this.mode,\n    required this.distanceM,\n    this.walkingDistanceM,\n    this.walkingDurationMin,\n    this.routeRefs = const [],\n""",
)

replace_once(
    listing,
    """    this.geoEntityId,\n    this.osm,\n    this.source,\n  });\n""",
    """    this.geoEntityId,\n    this.osm,\n    this.source,\n    this.walkingSource,\n  });\n""",
)

replace_once(
    listing,
    """        mode: j['mode']?.toString() ?? '',\n        distanceM: (j['distanceM'] as num?)?.round() ?? 0,\n        routeRefs:\n""",
    """        mode: j['mode']?.toString() ?? '',\n        distanceM: (j['distanceM'] as num?)?.round() ?? 0,\n        walkingDistanceM: (j['walkingDistanceM'] as num?)?.round(),\n        walkingDurationMin: (j['walkingDurationMin'] as num?)?.round(),\n        routeRefs:\n""",
)

replace_once(
    listing,
    """        osm:\n            j['osm'] is Map ? Map<String, dynamic>.from(j['osm'] as Map) : null,\n        source: j['source']?.toString(),\n      );\n""",
    """        osm:\n            j['osm'] is Map ? Map<String, dynamic>.from(j['osm'] as Map) : null,\n        source: j['source']?.toString(),\n        walkingSource: j['walkingSource']?.toString(),\n      );\n""",
)

replace_once(
    listing,
    """        'mode': mode,\n        'distanceM': distanceM,\n        'routeRefs': routeRefs,\n""",
    """        'mode': mode,\n        'distanceM': distanceM,\n        if (walkingDistanceM != null) 'walkingDistanceM': walkingDistanceM,\n        if (walkingDurationMin != null)\n          'walkingDurationMin': walkingDurationMin,\n        'routeRefs': routeRefs,\n""",
)

replace_once(
    listing,
    """        if (osm != null) 'osm': osm,\n        if (source != null) 'source': source,\n      };\n\n  String get displayLabel {\n    final routes = routeRefs.isEmpty ? '' : ' · ${routeRefs.join(', ')}';\n    return '$name$routes · $distanceM m';\n  }\n""",
    """        if (osm != null) 'osm': osm,\n        if (source != null) 'source': source,\n        if (walkingSource != null) 'walkingSource': walkingSource,\n      };\n\n  String get displayLabel {\n    final routes = routeRefs.isEmpty ? '' : ' · ${routeRefs.join(', ')}';\n    if (walkingDistanceM != null) {\n      final duration = walkingDurationMin == null\n          ? ''\n          : ' · ${walkingDurationMin!} min';\n      return '$name$routes · 🚶 ${walkingDistanceM!} m$duration';\n    }\n    return '$name$routes · $distanceM m';\n  }\n""",
)

replace_once(
    listing,
    """  final String? district; // intra-city district / neighbourhood | null\n  final String? metro; // nearest metro/transit station | null\n  final List<NearbyTransportStop> nearbyMetro;\n""",
    """  final String? district; // intra-city district / neighbourhood | null\n  final String? metro; // nearest metro/transit station | null\n  final int? metroWalkingDistanceM;\n  final int? metroWalkingDurationMin;\n  final List<NearbyTransportStop> nearbyMetro;\n""",
)

replace_once(
    listing,
    """    required this.district,\n    required this.metro,\n    this.nearbyMetro = const [],\n""",
    """    required this.district,\n    required this.metro,\n    this.metroWalkingDistanceM,\n    this.metroWalkingDurationMin,\n    this.nearbyMetro = const [],\n""",
)

replace_once(
    listing,
    """      district: _locationName(j['district']),\n      metro: _locationName(j['metro']),\n      nearbyMetro: (j['nearbyMetro'] as List?)\n""",
    """      district: _locationName(j['district']),\n      metro: _locationName(j['metro']),\n      metroWalkingDistanceM: (j['metroWalkingDistanceM'] as num?)?.round(),\n      metroWalkingDurationMin: (j['metroWalkingDurationMin'] as num?)?.round(),\n      nearbyMetro: (j['nearbyMetro'] as List?)\n""",
)

replace_once(
    listing,
    """        'district': district,\n        'metro': metro,\n        'nearbyMetro': nearbyMetro.map((e) => e.toJson()).toList(),\n""",
    """        'district': district,\n        'metro': metro,\n        if (metroWalkingDistanceM != null)\n          'metroWalkingDistanceM': metroWalkingDistanceM,\n        if (metroWalkingDurationMin != null)\n          'metroWalkingDurationMin': metroWalkingDurationMin,\n        'nearbyMetro': nearbyMetro.map((e) => e.toJson()).toList(),\n""",
)


detail = 'app/lib/screens/listing_detail.dart'

replace_once(
    detail,
    """  String? _money(MoneyAmount? value) {\n    if (value == null) return null;\n    final amount = value.amount % 1 == 0\n        ? value.amount.toInt().toString()\n        : value.amount.toString();\n    return '${value.approximate ? '≈ ' : ''}$amount ${value.currency ?? listing.currency}'\n        .trim();\n  }\n\n  /// Groups mirror the web's spec table sections: each group renders under\n""",
    """  String? _money(MoneyAmount? value) {\n    if (value == null) return null;\n    final amount = value.amount % 1 == 0\n        ? value.amount.toInt().toString()\n        : value.amount.toString();\n    return '${value.approximate ? '≈ ' : ''}$amount ${value.currency ?? listing.currency}'\n        .trim();\n  }\n\n  String _walkingDistanceLabel(int meters) {\n    if (meters < 1000) return s.lang == 'ru' ? '$meters м' : '$meters m';\n    final km = meters / 1000;\n    final value = meters % 1000 == 0\n        ? km.toStringAsFixed(0)\n        : km.toStringAsFixed(1);\n    return s.lang == 'ru' ? '$value км' : '$value km';\n  }\n\n  String? _metroLabel() {\n    final metro = listing.metro;\n    if (metro == null) return null;\n    final name = country?.locationLabel(listing.city, metro, kind: 'metro') ?? metro;\n    final distance = listing.metroWalkingDistanceM;\n    if (distance == null) return name;\n\n    final parts = <String>[name, '🚶 ${_walkingDistanceLabel(distance)}'];\n    final minutes = listing.metroWalkingDurationMin;\n    if (minutes != null) {\n      parts.add(s.lang == 'ru' ? '$minutes мин' : '$minutes min');\n    }\n    return parts.join(' · ');\n  }\n\n  /// Groups mirror the web's spec table sections: each group renders under\n""",
)

replace_once(
    detail,
    """      (\n        Icons.directions_subway_outlined,\n        'metro',\n        l.metro == null\n            ? null\n            : (country?.locationLabel(l.city, l.metro!, kind: 'metro') ??\n                l.metro),\n      ),\n""",
    """      (\n        Icons.directions_subway_outlined,\n        'metro',\n        _metroLabel(),\n      ),\n""",
)

print('Walking metro distance patch applied.')

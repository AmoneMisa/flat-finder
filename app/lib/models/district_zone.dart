import 'package:latlong2/latlong.dart';

/// One canonical geographic map zone from `@whiteslove/geo-catalog`.
class DistrictZone {
  final String id;
  final String? parentId;
  final String type;
  final String name;
  final String label;
  final double lat;
  final double lng;
  final double radiusM;
  final String colorHex;
  final String? mode;
  final List<String> routeRefs;
  final String? lineColorHex;
  final List<String> lineColorHexes;

  /// Real OSM/catalog boundary as one or more rings of [lat, lng] points.
  final List<List<LatLng>> boundaryRings;

  const DistrictZone({
    required this.id,
    required this.parentId,
    required this.type,
    required this.name,
    required this.label,
    required this.lat,
    required this.lng,
    required this.radiusM,
    required this.colorHex,
    required this.boundaryRings,
    this.mode,
    this.routeRefs = const [],
    this.lineColorHex,
    this.lineColorHexes = const [],
  });

  static List<List<LatLng>> _ringsFromGeoJson(Map<String, dynamic>? boundary) {
    if (boundary == null) return const [];
    final type = boundary['type'] as String?;
    final coords = boundary['coordinates'];
    List<LatLng> ring(List<dynamic> points) => points
        .map((p) => LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()))
        .toList();
    if (type == 'Polygon' && coords is List) {
      if (coords.isEmpty) return const [];
      return [ring((coords.first as List).cast<dynamic>())];
    }
    if (type == 'MultiPolygon' && coords is List) {
      return [
        for (final polygon in coords)
          if ((polygon as List).isNotEmpty)
            ring((polygon.first as List).cast<dynamic>()),
      ];
    }
    return const [];
  }

  static List<String> _strings(dynamic value) => value is List
      ? value
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(growable: false)
      : const [];

  factory DistrictZone.fromJson(Map<String, dynamic> j) => DistrictZone(
        id: j['id']?.toString() ?? '',
        parentId: j['parentId']?.toString(),
        type: j['type']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        label: j['label']?.toString() ?? j['name']?.toString() ?? '',
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        radiusM: (j['radiusM'] as num?)?.toDouble() ?? 400,
        colorHex: j['color']?.toString() ?? '#e0679a',
        mode: j['mode']?.toString(),
        routeRefs: _strings(j['routeRefs']),
        lineColorHex: j['lineColor']?.toString(),
        lineColorHexes: _strings(j['lineColors']),
        boundaryRings:
            _ringsFromGeoJson(j['boundary'] as Map<String, dynamic>?),
      );
}

/// All canonical map-zone layers for one city.
class MapZones {
  final List<DistrictZone> districtZones;
  final List<DistrictZone> regionZones;
  final List<DistrictZone> microdistrictMarkers;
  final List<DistrictZone> mahallaMarkers;
  final List<DistrictZone> quarterMarkers;
  final List<DistrictZone> quartalMarkers;
  final List<DistrictZone> areaZones;
  final List<DistrictZone> zoneMarkers;
  final List<DistrictZone> metroStations;
  final List<DistrictZone> parks;
  final List<DistrictZone> shoppingMalls;
  final List<DistrictZone> universities;
  final List<DistrictZone> schools;
  final List<DistrictZone> residentialComplexes;
  final List<DistrictZone> airports;
  final List<DistrictZone> railwayStations;
  final List<DistrictZone> busStations;
  final List<DistrictZone> transportStops;
  final List<DistrictZone> parkings;
  final DistrictZone? cityZone;

  const MapZones({
    this.districtZones = const [],
    this.regionZones = const [],
    this.microdistrictMarkers = const [],
    this.mahallaMarkers = const [],
    this.quarterMarkers = const [],
    this.quartalMarkers = const [],
    this.areaZones = const [],
    this.zoneMarkers = const [],
    this.metroStations = const [],
    this.parks = const [],
    this.shoppingMalls = const [],
    this.universities = const [],
    this.schools = const [],
    this.residentialComplexes = const [],
    this.airports = const [],
    this.railwayStations = const [],
    this.busStations = const [],
    this.transportStops = const [],
    this.parkings = const [],
    this.cityZone,
  });

  Iterable<DistrictZone> get allZones sync* {
    if (cityZone != null) yield cityZone!;
    yield* districtZones;
    yield* regionZones;
    yield* microdistrictMarkers;
    if (mahallaMarkers.isNotEmpty) {
      yield* mahallaMarkers;
    } else {
      yield* quartalMarkers;
    }
    yield* quarterMarkers;
    if (zoneMarkers.isNotEmpty) {
      yield* zoneMarkers;
    } else {
      yield* areaZones;
    }
    yield* metroStations;
    yield* parks;
    yield* shoppingMalls;
    yield* universities;
    yield* schools;
    yield* residentialComplexes;
    yield* airports;
    yield* railwayStations;
    yield* busStations;
    yield* transportStops;
    yield* parkings;
  }

  List<DistrictZone> transport(String mode) =>
      transportStops.where((zone) => zone.mode == mode).toList(growable: false);

  List<DistrictZone> get effectiveMahallas =>
      mahallaMarkers.isNotEmpty ? mahallaMarkers : quartalMarkers;

  List<DistrictZone> get effectiveZones =>
      zoneMarkers.isNotEmpty ? zoneMarkers : areaZones;

  DistrictZone? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final zone in allZones) {
      if (zone.id == id) return zone;
    }
    return null;
  }

  factory MapZones.fromJson(Map<String, dynamic> j) {
    List<DistrictZone> list(String key) => ((j[key] as List?) ?? const [])
        .map((e) => DistrictZone.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(growable: false);
    return MapZones(
      districtZones: list('districtZones'),
      regionZones: list('regionZones'),
      microdistrictMarkers: list('microdistrictMarkers'),
      mahallaMarkers: list('mahallaMarkers').isNotEmpty
          ? list('mahallaMarkers')
          : list('quartalMarkers'),
      quarterMarkers: list('quarterMarkers'),
      quartalMarkers: list('quartalMarkers'),
      areaZones: list('areaZones'),
      zoneMarkers: list('zoneMarkers').isNotEmpty
          ? list('zoneMarkers')
          : list('areaZones'),
      metroStations: list('metroStations'),
      parks: list('parks'),
      shoppingMalls: list('shoppingMalls'),
      universities: list('universities'),
      schools: list('schools'),
      residentialComplexes: list('residentialComplexes'),
      airports: list('airports'),
      railwayStations: list('railwayStations'),
      busStations: list('busStations'),
      transportStops: list('transportStops'),
      parkings: list('parkings'),
      cityZone: j['cityZone'] is Map
          ? DistrictZone.fromJson(
              Map<String, dynamic>.from(j['cityZone'] as Map),
            )
          : null,
    );
  }
}

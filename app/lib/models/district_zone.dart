import 'package:latlong2/latlong.dart';

/// One canonical geographic map zone from `@whiteslove/geo-catalog`.
///
/// The backend keeps the catalog's identity, hierarchy and boundary intact so
/// Flutter can render and select districts, microdistricts, mahallas and local
/// areas without inventing a parallel geography model.
class DistrictZone {
  final String id;
  final String? parentId;
  final String type;
  final String name;
  final String label;
  final double lat;
  final double lng;
  final double radiusM;
  final String colorHex; // e.g. "#e0679a"

  /// Real OSM/catalog boundary as one or more rings of [lat, lng] points,
  /// already converted from GeoJSON's [lng, lat] order. Empty when the catalog
  /// only has a centroid; callers may use the catalog accuracy as a visual
  /// fallback circle in that case.
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
        boundaryRings:
            _ringsFromGeoJson(j['boundary'] as Map<String, dynamic>?),
      );
}

/// All canonical map-zone layers for one city. The legacy `*Markers` names are
/// kept in the wire model for backward compatibility, but Flutter renders any
/// available boundary as a real polygon and only falls back to a centroid
/// circle when the geo catalog has no boundary for that entity.
class MapZones {
  final List<DistrictZone> districtZones;
  final List<DistrictZone> microdistrictMarkers;
  final List<DistrictZone> quartalMarkers; // mahallas
  final List<DistrictZone> areaZones;
  final List<DistrictZone> metroStations;
  final DistrictZone? cityZone;

  const MapZones({
    this.districtZones = const [],
    this.microdistrictMarkers = const [],
    this.quartalMarkers = const [],
    this.areaZones = const [],
    this.metroStations = const [],
    this.cityZone,
  });

  Iterable<DistrictZone> get allZones sync* {
    if (cityZone != null) yield cityZone!;
    yield* districtZones;
    yield* microdistrictMarkers;
    yield* quartalMarkers;
    yield* areaZones;
    yield* metroStations;
  }

  DistrictZone? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final zone in allZones) {
      if (zone.id == id) return zone;
    }
    return null;
  }

  factory MapZones.fromJson(Map<String, dynamic> j) {
    List<DistrictZone> list(String key) => ((j[key] as List?) ?? const [])
        .map((e) => DistrictZone.fromJson(e as Map<String, dynamic>))
        .toList();
    return MapZones(
      districtZones: list('districtZones'),
      microdistrictMarkers: list('microdistrictMarkers'),
      quartalMarkers: list('quartalMarkers'),
      areaZones: list('areaZones'),
      metroStations: list('metroStations'),
      cityZone: j['cityZone'] is Map
          ? DistrictZone.fromJson(
              Map<String, dynamic>.from(j['cityZone'] as Map),
            )
          : null,
    );
  }
}

import 'package:latlong2/latlong.dart';

/// One administrative district's map colour zone — mirrors whiteslove.me's
/// `useDistrictZones.ts` district layer (same palette, same boundary data
/// from `@whiteslove/geo-catalog`, served by the backend's
/// `/api/district-zones` since Dart can't import that catalog directly).
class DistrictZone {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final double radiusM;
  final String colorHex; // e.g. "#e0679a"
  /// Real OSM boundary as one or more rings of [lat, lng] points, already
  /// converted from GeoJSON's [lng, lat] order. Empty when the catalog only
  /// has a centroid for this district (caller falls back to a circle).
  final List<List<LatLng>> boundaryRings;

  const DistrictZone({
    required this.id,
    required this.name,
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
      // First ring is the outer boundary; holes aren't rendered (Leaflet
      // side doesn't special-case them for districts either).
      if (coords.isEmpty) return const [];
      return [ring((coords.first as List).cast<dynamic>())];
    }
    if (type == 'MultiPolygon' && coords is List) {
      return [
        for (final polygon in coords)
          if ((polygon as List).isNotEmpty) ring((polygon.first as List).cast<dynamic>()),
      ];
    }
    return const [];
  }

  factory DistrictZone.fromJson(Map<String, dynamic> j) => DistrictZone(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        radiusM: (j['radiusM'] as num?)?.toDouble() ?? 400,
        colorHex: j['color']?.toString() ?? '#e0679a',
        boundaryRings: _ringsFromGeoJson(j['boundary'] as Map<String, dynamic>?),
      );
}

/// All four of a city's map zone layers — mirrors the site's
/// useDistrictZones.ts return shape and its four toolbar toggles
/// (Districts/Microdistricts/Quartals/Areas).
class MapZones {
  final List<DistrictZone> districtZones;
  final List<DistrictZone> microdistrictMarkers;
  final List<DistrictZone> quartalMarkers; // mahallas
  final List<DistrictZone> areaZones;

  const MapZones({
    this.districtZones = const [],
    this.microdistrictMarkers = const [],
    this.quartalMarkers = const [],
    this.areaZones = const [],
  });

  factory MapZones.fromJson(Map<String, dynamic> j) {
    List<DistrictZone> list(String key) => ((j[key] as List?) ?? const [])
        .map((e) => DistrictZone.fromJson(e as Map<String, dynamic>))
        .toList();
    return MapZones(
      districtZones: list('districtZones'),
      microdistrictMarkers: list('microdistrictMarkers'),
      quartalMarkers: list('quartalMarkers'),
      areaZones: list('areaZones'),
    );
  }
}

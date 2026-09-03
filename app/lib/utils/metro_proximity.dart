import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Metro proximity as a *client-side* filter: "within N metres of any
/// selected station, and only in this compass arc".
///
/// The backend understands a single `metro` station plus a plain `metroMaxM`
/// radius and nothing else -- there is no bearing or multi-station parameter
/// -- so the directional wedge and the union over several stations are
/// evaluated here, against listings the feed already returned. This is a
/// straight port of the web client's `useMetroProximity.ts`; keep the two in
/// step if the rule ever changes.
///
/// Bearings are degrees clockwise from north, the convention the map's drag
/// handles and the `metroArc` query parameter both use.

class MetroPoint {
  const MetroPoint({required this.name, required this.lat, required this.lng});
  final String name;
  final double lat;
  final double lng;
}

class MetroProximity {
  const MetroProximity({
    this.stations = const [],
    this.maxM,
    this.bearingFrom,
    this.bearingTo,
  });

  final List<MetroPoint> stations;

  /// Null means "no distance limit", matching an unset metroMaxM.
  final double? maxM;

  /// Both null means the full circle.
  final double? bearingFrom;
  final double? bearingTo;

  /// True when the filter is inert and every listing should pass untouched.
  bool get isEmpty {
    if (stations.isEmpty) return true;
    final hasArc = bearingFrom != null && bearingTo != null;
    return maxM == null && !hasArc;
  }
}

const _earthRadiusM = 6371008.8;
double _toRad(double deg) => deg * math.pi / 180;
double _toDeg(double rad) => rad * 180 / math.pi;

double normalizeBearing(double deg) {
  final wrapped = deg % 360;
  return wrapped < 0 ? wrapped + 360 : wrapped;
}

double metresBetween(LatLng a, LatLng b) {
  final lat1 = _toRad(a.latitude);
  final lat2 = _toRad(b.latitude);
  final dLat = lat2 - lat1;
  final dLng = _toRad(b.longitude - a.longitude);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthRadiusM * math.asin(math.min(1, math.sqrt(h)));
}

/// Initial great-circle bearing from [origin] to [target], in [0, 360).
double bearingBetween(LatLng origin, LatLng target) {
  final lat1 = _toRad(origin.latitude);
  final lat2 = _toRad(target.latitude);
  final dLng = _toRad(target.longitude - origin.longitude);
  final y = math.sin(dLng) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  return normalizeBearing(_toDeg(math.atan2(y, x)));
}

/// Point at [distanceM] from [origin] along [bearingDeg]. Used to draw the
/// wedge and to place the drag handles along its arc.
LatLng destinationPoint(LatLng origin, double bearingDeg, double distanceM) {
  final angular = distanceM / _earthRadiusM;
  final lat1 = _toRad(origin.latitude);
  final lng1 = _toRad(origin.longitude);
  final theta = _toRad(bearingDeg);
  final lat2 = math.asin(
    math.sin(lat1) * math.cos(angular) +
        math.cos(lat1) * math.sin(angular) * math.cos(theta),
  );
  final lng2 = lng1 +
      math.atan2(
        math.sin(theta) * math.sin(angular) * math.cos(lat1),
        math.cos(angular) - math.sin(lat1) * math.sin(lat2),
      );
  return LatLng(_toDeg(lat2), normalizeBearing(_toDeg(lng2) + 180) - 180);
}

/// Arc containment, wrap-safe. An arc is stored as the clockwise sweep from
/// [from] to [to], so 340->20 is the 40 degree wedge straddling north rather
/// than the 320 degree one going the long way round.
bool bearingWithinArc(double bearing, double from, double to) {
  final sweep = normalizeBearing(to - from);
  // A zero-width arc would silently reject everything; treat it as the full
  // circle, which is what "the handles have not been separated yet" means.
  if (sweep == 0) return true;
  return normalizeBearing(bearing - from) <= sweep;
}

/// The traced wedge outline: station -> arc -> station. A full circle closes
/// on itself; a wedge closes through its apex.
List<LatLng> sectorPolygon(
  LatLng station,
  double radiusM, {
  double? from,
  double? to,
  int segments = 48,
}) {
  final full = from == null || to == null;
  final start = full ? 0.0 : normalizeBearing(from);
  final rawSweep = full ? 360.0 : normalizeBearing(to - from);
  final sweep = full ? 360.0 : (rawSweep == 0 ? 360.0 : rawSweep);
  final steps = math.max(2, (segments * sweep / 360).round());
  final arc = List<LatLng>.generate(
    steps + 1,
    (index) =>
        destinationPoint(station, start + sweep * index / steps, radiusM),
  );
  return full ? arc : [LatLng(station.latitude, station.longitude), ...arc];
}

bool _matchesStation(
    LatLng listing, MetroPoint station, MetroProximity proximity) {
  if (proximity.maxM != null &&
      metresBetween(station.toLatLng(), listing) > proximity.maxM!) {
    return false;
  }
  if (proximity.bearingFrom == null || proximity.bearingTo == null) return true;
  return bearingWithinArc(
    bearingBetween(station.toLatLng(), listing),
    proximity.bearingFrom!,
    proximity.bearingTo!,
  );
}

extension on MetroPoint {
  LatLng toLatLng() => LatLng(lat, lng);
}

/// Keeps items near *any* selected station -- a union, not an intersection:
/// picking two stations means "either is fine", which is how a rider reads
/// it. [locationOf] returns null for an item with no usable coordinates,
/// which is kept rather than dropped: the backend geocodes better than the
/// client can, so a missing lat/lng is a gap in the map data, not evidence
/// the flat is far away.
List<T> applyMetroProximity<T>(
  List<T> items,
  MetroProximity proximity,
  LatLng? Function(T item) locationOf,
) {
  if (proximity.isEmpty) return items;
  return items.where((item) {
    final point = locationOf(item);
    if (point == null) return true;
    return proximity.stations
        .any((station) => _matchesStation(point, station, proximity));
  }).toList(growable: false);
}

const List<String> compassOrder = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

/// The 8-point compass name for an arc, taken from its midpoint.
String compassPointFor(double from, double to) {
  final middle = normalizeBearing(from + normalizeBearing(to - from) / 2);
  return compassOrder[(middle / 45).round() % 8];
}

/// The arc a compass point stands for: its 45 degree slice, centred on the
/// point.
(double from, double to) arcForCompassPoint(String point) {
  final centre = compassOrder.indexOf(point) * 45.0;
  return (normalizeBearing(centre - 22.5), normalizeBearing(centre + 22.5));
}

/// How close a tap must land to a station dot to count as hitting it, in
/// logical pixels. Deliberately pixels rather than metres: a fixed metre
/// radius covers most of the screen when zoomed out to a city and a sliver
/// when zoomed into a street, whereas the dot being aimed at is the same
/// size at every zoom.
const double metroTapSlopPx = 24;

/// What a map tap near the nearest metro station means: the radius to adopt,
/// or null when the tap belongs to whatever is underneath (a district or
/// local-area polygon) instead.
///
/// The rule follows what is actually drawn. With no selection the three
/// preset rings are on screen and are genuinely clickable, so a tap inside
/// the outermost one picks that band's distance. Once a station is chosen
/// those rings are gone, so only the dot itself can mean a station -- before
/// this, any tap within 1000m of a station was swallowed by it, which at
/// city zoom is most of the visible map.
double? metroTapRadiusM({
  required double screenDistancePx,
  required double metresFromStation,
  required bool hasSelection,
  double slopPx = metroTapSlopPx,
}) {
  final onDot = screenDistancePx <= slopPx;
  if (hasSelection) return onDot ? defaultMetroRadiusM : null;
  if (onDot) return defaultMetroRadiusM;
  if (metresFromStation > 1000) return null;
  if (metresFromStation <= 200) return 200;
  if (metresFromStation <= 500) return 500;
  return 1000;
}

/// The radius a freshly picked station starts at, before any drag.
const double defaultMetroRadiusM = 500;
const double metroMinRadiusM = 100;
const double metroMaxRadiusM = 5000;

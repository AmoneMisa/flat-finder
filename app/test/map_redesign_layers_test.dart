import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile map keeps grouped layer controls and semantic cluster tone', () {
    final source = File('lib/widgets/map_view.dart').readAsStringSync();
    expect(source, contains('_MapLayerGroup.territories'));
    expect(source, contains('_MapLayerGroup.transport'));
    expect(source, contains('_MapLayerGroup.poi'));
    expect(source, contains('tone: _priceToneForGroup(group.listings)'));
    expect(source, contains('color: _neutralMapMarker'));
  });

  test('mobile map exposes canonical transport and expanded POI layers', () {
    final source = File('lib/widgets/map_view.dart').readAsStringSync();
    final model = File('lib/models/district_zone.dart').readAsStringSync();
    for (final token in <String>[
      "transport('bus')",
      "transport('tram')",
      "transport('trolleybus')",
      "transport('minibus')",
      "transport('funicular')",
      'regionZones',
      'effectiveMahallas',
      'quarterMarkers',
      'effectiveZones',
      'residentialComplexes',
      'schools',
      'airports',
      'railwayStations',
      'busStations',
      'parkings',
    ]) {
      expect(source + model, contains(token));
    }
  });
}

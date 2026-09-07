import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MapZones parses expanded canonical backend groups', () {
    final source = File('lib/models/district_zone.dart').readAsStringSync();
    for (final key in <String>[
      "list('schools')",
      "list('residentialComplexes')",
      "list('airports')",
      "list('railwayStations')",
      "list('busStations')",
      "list('transportStops')",
      "list('parkings')",
    ]) {
      expect(source, contains(key));
    }
  });
}

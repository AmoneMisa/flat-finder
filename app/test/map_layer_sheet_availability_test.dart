import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('layer sheet gates toggles on canonical data availability', () {
    final source = File('lib/widgets/map_view.dart').readAsStringSync();
    expect(source, contains('available: _zones.transport'));
    expect(source, contains('available: _zones.residentialComplexes.isNotEmpty'));
    expect(source, contains('available: _zones.schools.isNotEmpty'));
  });
}

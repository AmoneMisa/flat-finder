import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('count clusters use neutral center with price tone on the border', () {
    final source = File('lib/widgets/map_view.dart').readAsStringSync();
    expect(source, contains('final ring = priceToneColor(tone)'));
    expect(source, contains('color: _neutralMapMarker'));
    expect(source, contains('border: Border.all(color: ring, width: 3)'));
  });
}

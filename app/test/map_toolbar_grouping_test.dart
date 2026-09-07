import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('map toolbar exposes three grouped layer entry points', () {
    final source = File('lib/widgets/map_view.dart').readAsStringSync();
    expect(
        RegExp(r'_openLayerSheet\(_MapLayerGroup\.').allMatches(source).length,
        greaterThanOrEqualTo(3));
    expect(
        source, contains("_mapCopy(context, 'Выделить область', 'Draw area')"));
    expect(source, contains('Icons.crop_free'));
  });
}

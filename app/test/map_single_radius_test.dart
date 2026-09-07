import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('redesigned map does not render three discovery radii together', () {
    final source = File('lib/widgets/map_view.dart').readAsStringSync();
    expect(source, isNot(contains('_metro200Color')));
    expect(source, isNot(contains('_metro500Color')));
    expect(source, isNot(contains('_metro1000Color')));
    expect(source, contains('_shapeRadiusM(filters)'));
  });
}

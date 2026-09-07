import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile map uses compact icon controls and bottom sheets for dense layers', () {
    final source = File('lib/widgets/map_view.dart').readAsStringSync();
    expect(source, contains('showModalBottomSheet<void>'));
    expect(source, contains('_openLayerSheet(_MapLayerGroup.territories)'));
    expect(source, contains('_openLayerSheet(_MapLayerGroup.transport)'));
    expect(source, contains('_openLayerSheet(_MapLayerGroup.poi)'));
    expect(source, isNot(contains('SingleChildScrollView(\n              scrollDirection: Axis.horizontal')));
  });
}

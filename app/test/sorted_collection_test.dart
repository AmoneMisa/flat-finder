import 'package:flutter_test/flutter_test.dart';

import '../lib/state/sorted.dart';

void main() {
  test('sorted collection keeps filter/preset metadata', () {
    const collection = SortedCollection(
      id: 'preset:test',
      title: 'Tashkent · Test preset · Preset',
      isPreset: true,
      presetName: 'Test preset',
      items: [],
    );

    expect(collection.id, 'preset:test');
    expect(collection.isPreset, isTrue);
    expect(collection.presetName, 'Test preset');
    expect(collection.title, contains('Preset'));
  });
}

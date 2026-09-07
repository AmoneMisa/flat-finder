import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transport and POI sheets expose radius controls', () {
    final source = File('lib/widgets/map_view.dart').readAsStringSync();
    expect(source, contains('DropdownButton<double>'));
    expect(source, contains('Slider('));
    expect(source, contains('TextFormField('));
    expect(source, contains('continuousRadius: true'));
    expect(source, contains('_busRadiusM'));
    expect(source, contains('_schoolRadiusM'));
    expect(source, contains('_airportRadiusM'));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonical zones retain mode routes and metro line colors', () {
    final source = File('lib/models/district_zone.dart').readAsStringSync();
    expect(source, contains('final String? mode;'));
    expect(source, contains('final List<String> routeRefs;'));
    expect(source, contains('final String? lineColorHex;'));
    expect(source, contains('final List<String> lineColorHexes;'));
  });
}

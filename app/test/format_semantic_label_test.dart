import 'package:flat_finder/l10n/strings.dart';
import 'package:flat_finder/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('semanticLabel', () {
    test('localizes canonical AI labels to Russian UI', () {
      const s = AppStrings('ru');

      expect(semanticLabel('Railway station', s), 'Железнодорожный вокзал');
      expect(semanticLabel('train_station', s), 'Железнодорожный вокзал');
      expect(semanticLabel('Bus station', s), 'Автовокзал');
    });

    test('keeps English labels in English UI', () {
      const s = AppStrings('en');

      expect(semanticLabel('Railway station', s), 'Railway station');
      expect(semanticLabel('metro-station', s), 'Metro station');
    });

    test('does not translate dynamic place names', () {
      const s = AppStrings('ru');

      expect(semanticLabel('Саодат', s), 'Саодат');
      expect(semanticLabel('Registan', s), 'Registan');
    });
  });
}

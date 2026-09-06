import 'package:flat_finder/l10n/review_strings.dart';
import 'package:flat_finder/l10n/strings.dart';
import 'package:flat_finder/state/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Size? _minimumSize(ButtonStyle? style) =>
    style?.minimumSize?.resolve(const <WidgetState>{});

void main() {
  test('saved-listing counts use correct Russian plural forms', () {
    final s = AppStrings('ru');
    expect(s.apartmentsCount(1), '1 квартира');
    expect(s.apartmentsCount(2), '2 квартиры');
    expect(s.apartmentsCount(5), '5 квартир');
    expect(s.apartmentsCount(11), '11 квартир');
    expect(s.apartmentsCount(21), '21 квартира');
    expect(AppStrings('en').apartmentsCount(1), '1 apartment');
    expect(AppStrings('en').apartmentsCount(2), '2 apartments');
  });

  test('primary button themes keep a 48dp minimum touch height', () {
    for (final name in kThemeOptions) {
      final theme = buildTheme(name);
      expect(_minimumSize(theme.filledButtonTheme.style)?.height, greaterThanOrEqualTo(48));
      expect(_minimumSize(theme.elevatedButtonTheme.style)?.height, greaterThanOrEqualTo(48));
      expect(_minimumSize(theme.outlinedButtonTheme.style)?.height, greaterThanOrEqualTo(48));
    }
  });
}

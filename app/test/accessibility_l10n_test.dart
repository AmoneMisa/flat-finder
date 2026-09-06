import 'package:flat_finder/l10n/review_strings.dart';
import 'package:flat_finder/l10n/strings.dart';
import 'package:flat_finder/screens/settings_screen.dart';
import 'package:flat_finder/services/api_service.dart';
import 'package:flat_finder/state/presets.dart';
import 'package:flat_finder/state/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Size? _minimumSize(ButtonStyle? style) =>
    style?.minimumSize?.resolve(const <WidgetState>{});

void main() {
  test('saved-listing counts use correct Russian plural forms', () {
    const s = AppStrings('ru');
    expect(s.apartmentsCount(1), '1 квартира');
    expect(s.apartmentsCount(2), '2 квартиры');
    expect(s.apartmentsCount(5), '5 квартир');
    expect(s.apartmentsCount(11), '11 квартир');
    expect(s.apartmentsCount(21), '21 квартира');
    expect(const AppStrings('en').apartmentsCount(1), '1 apartment');
    expect(const AppStrings('en').apartmentsCount(2), '2 apartments');
  });

  test('review and map chrome is localized outside widgets', () {
    const ru = AppStrings('ru');
    const en = AppStrings('en');
    expect(ru.reviewCollectionsMenu, 'Просмотреть подборки');
    expect(en.reviewCollectionsMenu, 'Review collections');
    expect(ru.loadingData, 'Загружаем данные…');
    expect(en.loadingData, 'Loading data…');
    expect(ru.placeWorkOnMap, 'Указать работу на карте');
    expect(en.placeWorkOnMap, 'Set work location on map');
    expect(ru.metresShort, 'м');
    expect(en.metresShort, 'm');
    expect(ru.kilometresShort, 'км');
    expect(en.kilometresShort, 'km');
    expect(ru.metroRadiusHandle, 'Радиус метро');
    expect(en.metroRadiusHandle, 'Metro radius');
    expect(ru.metroArcStartHandle, 'Начало сектора метро');
    expect(en.metroArcEndHandle, 'Metro sector end');
    expect(
      ru.adjustWithDragOrButtons,
      'Перетащите или используйте действия увеличить и уменьшить',
    );
    expect(
      en.adjustWithDragOrButtons,
      'Drag or use the increase and decrease actions',
    );
  });

  test('primary button themes keep a 48dp minimum touch height', () {
    for (final name in kThemeOptions) {
      final theme = buildTheme(name);
      expect(
        _minimumSize(theme.filledButtonTheme.style)?.height,
        greaterThanOrEqualTo(48),
      );
      expect(
        _minimumSize(theme.elevatedButtonTheme.style)?.height,
        greaterThanOrEqualTo(48),
      );
      expect(
        _minimumSize(theme.outlinedButtonTheme.style)?.height,
        greaterThanOrEqualTo(48),
      );
    }
  });

  testWidgets('settings RadioGroups update theme and nullable currency',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final settings = SettingsState();
    final api = ApiService(baseUrl: 'https://example.test');
    final presets = PresetsState(api);
    addTearDown(() {
      presets.dispose();
      settings.dispose();
      api.dispose();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsState>.value(value: settings),
          ChangeNotifierProvider<PresetsState>.value(value: presets),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );

    final lightTheme = find.byWidgetPredicate(
      (widget) => widget is RadioListTile<String> && widget.value == 'light',
    );
    expect(lightTheme, findsOneWidget);
    await tester.tap(lightTheme);
    await tester.pump();
    expect(settings.themeName, 'light');

    await settings.setDisplayCurrency('USD');
    await tester.pump();
    final nativeCurrency = find.byWidgetPredicate(
      (widget) => widget is RadioListTile<String?> && widget.value == null,
    );
    expect(nativeCurrency, findsOneWidget);
    await tester.ensureVisible(nativeCurrency);
    await tester.tap(nativeCurrency);
    await tester.pump();
    expect(settings.displayCurrency, isNull);
  });
}

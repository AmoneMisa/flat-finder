from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    return text.replace(old, new, 1)


# Centralized feature strings: keep screen widgets free of inline RU/EN forks.
l10n = Path('app/lib/l10n/review_strings.dart')
l10n.write_text("""import 'strings.dart';

/// Localized copy used by the saved-listing review/sorting flow.
///
/// Kept next to [AppStrings] rather than branching on language inside widgets.
extension ReviewStrings on AppStrings {
  bool get _ru => lang == 'ru';

  String get noCity => _ru ? 'Без города' : 'No city';
  String get chooseCollectionsToReview =>
      _ru ? 'Какие подборки посмотреть?' : 'Which collections do you want to review?';
  String get cancel => _ru ? 'Отмена' : 'Cancel';
  String get start => _ru ? 'Начать' : 'Start';
  String get sortedTitle => _ru ? 'Отсортированные' : 'Sorted';
  String get sortedEmpty => _ru
      ? 'Здесь появятся квартиры после свайпа вправо'
      : 'Apartments sorted with a right swipe will appear here';
  String get presetLabel => _ru ? 'Пресет' : 'Preset';
  String get deleteCollection => _ru ? 'Удалить список' : 'Delete collection';
  String get reviewSelectionTitle => _ru ? 'Просмотр подборки' : 'Review selection';
  String get selectionReviewed => _ru ? 'Подборка просмотрена' : 'Selection reviewed';
  String get swipeReviewHint =>
      _ru ? '← Скрыть   •   Отсортировать →' : '← Hide   •   Sort →';
  String get sortAction => _ru ? 'Отсортировать' : 'Sort';
  String get roomsUnitShort => _ru ? 'комн.' : 'rooms';

  String apartmentsCount(int count) {
    if (!_ru) return '$count ${count == 1 ? 'apartment' : 'apartments'}';
    final mod10 = count.abs() % 10;
    final mod100 = count.abs() % 100;
    final word = mod10 == 1 && mod100 != 11
        ? 'квартира'
        : (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)
            ? 'квартиры'
            : 'квартир');
    return '$count $word';
  }
}
""", encoding='utf-8')

# Home: localize review dialog and restore 48dp header action targets.
path = Path('app/lib/screens/home_screen.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    "import '../models/filters.dart';\n",
    "import '../l10n/review_strings.dart';\nimport '../models/filters.dart';\n",
    'home review l10n import',
)
old = """  Future<void> _openSwipeReview() async {
    final grouped = context.read<FavoritesState>().grouped();
    final groups = <String, List<Listing>>{};
    for (final country in grouped.entries) {
      for (final city in country.value.entries) {
        groups['${country.key} · ${city.key.isEmpty ? 'Без города' : city.key}'] =
            city.value;
      }
    }
    if (groups.isEmpty) return;
    final selected = <String>{};
    final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
              builder: (context, setLocal) => AlertDialog(
                title: const Text('Какие подборки посмотреть?'),
                content: SizedBox(
                    width: 420,
                    child: ListView(shrinkWrap: true, children: [
                      for (final entry in groups.entries)
                        CheckboxListTile(
                          value: selected.contains(entry.key),
                          title: Text(entry.key),
                          subtitle: Text('${entry.value.length} квартир'),
                          onChanged: (value) => setLocal(() => value == true
                              ? selected.add(entry.key)
                              : selected.remove(entry.key)),
                        ),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Отмена')),
                  FilledButton(
                      onPressed: selected.isEmpty
                          ? null
                          : () => Navigator.pop(dialogContext, true),
                      child: const Text('Начать')),
                ],
              ),
            ));
    if (ok != true || !mounted) return;
    final unique = <String, Listing>{};
    for (final name in selected) {
      for (final listing in groups[name]!)
        unique[listingKey(listing)] = listing;
    }
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SwipeReviewScreen(listings: unique.values.toList())));
  }
"""
new = """  Future<void> _openSwipeReview() async {
    final settings = context.read<SettingsState>();
    final grouped = context.read<FavoritesState>().grouped();
    final groups = <String, List<Listing>>{};
    for (final country in grouped.entries) {
      final countryLabel = settings.s.countryName(country.key, country.key);
      for (final city in country.value.entries) {
        final cityLabel = city.key.isEmpty ? settings.s.noCity : city.key;
        groups['$countryLabel · $cityLabel'] = city.value;
      }
    }
    if (groups.isEmpty) return;
    final selected = <String>{};
    final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
              builder: (context, setLocal) => AlertDialog(
                title: Text(settings.s.chooseCollectionsToReview),
                content: SizedBox(
                    width: 420,
                    child: ListView(shrinkWrap: true, children: [
                      for (final entry in groups.entries)
                        CheckboxListTile(
                          value: selected.contains(entry.key),
                          title: Text(entry.key),
                          subtitle: Text(settings.s.apartmentsCount(entry.value.length)),
                          onChanged: (value) => setLocal(() => value == true
                              ? selected.add(entry.key)
                              : selected.remove(entry.key)),
                        ),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: Text(settings.s.cancel)),
                  FilledButton(
                      onPressed: selected.isEmpty
                          ? null
                          : () => Navigator.pop(dialogContext, true),
                      child: Text(settings.s.start)),
                ],
              ),
            ));
    if (ok != true || !mounted) return;
    final unique = <String, Listing>{};
    for (final name in selected) {
      for (final listing in groups[name]!) {
        unique[listingKey(listing)] = listing;
      }
    }
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SwipeReviewScreen(listings: unique.values.toList())));
  }
"""
text = replace_once(text, old, new, 'localized review dialog')
text = replace_once(
    text,
    """    final headerActionStyle = IconButton.styleFrom(
      minimumSize: const Size(30, 38),
      maximumSize: const Size(30, 38),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
""",
    """    final headerActionStyle = IconButton.styleFrom(
      minimumSize: const Size(48, 48),
      maximumSize: const Size(48, 48),
      padding: EdgeInsets.zero,
    );
""",
    'home header tap targets',
)
text = replace_once(text, '        toolbarHeight: 52,\n', '        toolbarHeight: 56,\n', 'home toolbar height')
path.write_text(text, encoding='utf-8')

# Saved/sorted screen copy belongs to l10n, not build-time language branches.
path = Path('app/lib/screens/sorted_screen.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    "import '../state/settings.dart';\n",
    "import '../l10n/review_strings.dart';\nimport '../state/settings.dart';\n",
    'sorted l10n import',
)
text = text.replace("    final ru = settings.lang == 'ru';\n", '')
text = text.replace("appBar: AppBar(title: Text(ru ? 'Отсортированные' : 'Sorted'))", "appBar: AppBar(title: Text(settings.s.sortedTitle))")
text = text.replace("""              child: Text(
                ru
                    ? 'Здесь появятся квартиры после свайпа вправо'
                    : 'Apartments sorted with a right swipe will appear here',
                textAlign: TextAlign.center,
              ),
""", """              child: Text(
                settings.s.sortedEmpty,
                textAlign: TextAlign.center,
              ),
""")
text = text.replace("""                      collection.isPreset
                          ? (ru
                              ? 'Пресет · ${collection.items.length} квартир'
                              : 'Preset · ${collection.items.length} apartments')
                          : (ru
                              ? '${collection.items.length} квартир'
                              : '${collection.items.length} apartments'),
""", """                      collection.isPreset
                          ? '${settings.s.presetLabel} · ${settings.s.apartmentsCount(collection.items.length)}'
                          : settings.s.apartmentsCount(collection.items.length),
""")
text = text.replace("label: Text(ru ? 'Пресет' : 'Preset'),", "label: Text(settings.s.presetLabel),")
text = text.replace("tooltip: ru ? 'Удалить список' : 'Delete collection',", "tooltip: settings.s.deleteCollection,")
if "settings.lang == 'ru'" in text or "'Отсортированные'" in text:
    raise SystemExit('sorted screen still contains inline language branch')
path.write_text(text, encoding='utf-8')

# Swipe review: use existing AppStrings keys plus the feature l10n extension.
path = Path('app/lib/screens/swipe_review_screen.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    "import '../models/filters.dart';\n",
    "import '../l10n/review_strings.dart';\nimport '../models/filters.dart';\n",
    'swipe l10n import',
)
text = text.replace("""        title: settings.lang == 'ru'
            ? '${preset.name} · Пресет'
            : '${preset.name} · Preset',
""", """        title: '${preset.name} · ${settings.s.presetLabel}',
""")
text = text.replace("add(settings.lang == 'ru' ? 'Продажа' : 'Sale');", "add(settings.t('sale'));")
text = text.replace("""          add(filters.roomOnly
              ? (settings.lang == 'ru' ? 'Комната' : 'Room rent')
              : (settings.lang == 'ru' ? 'Долгосрочная аренда' : 'Long rent'));
""", """          add(filters.roomOnly
              ? settings.t('cardRoomRent')
              : settings.t('longRentLong'));
""")
text = text.replace("add(settings.lang == 'ru' ? 'Посуточно' : 'Short rent');", "add(settings.t('shortRentLong'));")
text = text.replace("add(settings.lang == 'ru' ? 'Собственник' : 'Owner');", "add(settings.t('owner'));")
text = text.replace("add(settings.lang == 'ru' ? 'Агентство' : 'Agency');", "add(settings.t('agency'));")
text = text.replace("settings.lang == 'ru' ? 'комн.' : 'rooms',", "settings.s.roomsUnitShort,")
text = text.replace("""      if (filters.pets)
        add(settings.lang == 'ru' ? 'Можно с животными' : 'Pets allowed');
""", """      if (filters.pets) {
        add(settings.t('badgePet'));
      }
""")
text = text.replace("add(settings.lang == 'ru' ? 'Можно с детьми' : 'Children allowed');", "add(settings.t('badgeChildren'));")
text = text.replace("""      if (filters.withPhotos)
        add(settings.lang == 'ru' ? 'С фото' : 'With photos');
""", """      if (filters.withPhotos) {
        add(settings.t('withPhotos'));
      }
""")
text = text.replace("""    final title = parts.isEmpty
        ? (settings.lang == 'ru' ? 'Отсортированные' : 'Sorted')
        : parts.join(' · ');
""", """    final title = parts.isEmpty ? settings.s.sortedTitle : parts.join(' · ');
""")
text = text.replace("    final ru = settings.lang == 'ru';\n", '')
text = text.replace("title: Text(ru ? 'Просмотр подборки' : 'Review selection'),", "title: Text(settings.s.reviewSelectionTitle),")
text = text.replace("Text(ru ? 'Подборка просмотрена' : 'Selection reviewed'),", "Text(settings.s.selectionReviewed),")
text = text.replace("""                      ru
                          ? '← Скрыть   •   Отсортировать →'
                          : '← Hide   •   Sort →',
""", """                      settings.s.swipeReviewHint,
""")
text = text.replace("label: ru ? 'Отсортировать' : 'Sort',", "label: settings.s.sortAction,")
text = text.replace("label: ru ? 'Скрыть' : 'Hide',", "label: settings.t('hideListing'),")
if "settings.lang == 'ru'" in text or "final ru =" in text:
    raise SystemExit('swipe review still contains inline language branch')
path.write_text(text, encoding='utf-8')

# Theme-level minimum action height: compact visual density may remain, but the
# actual touch target must stay at least 48dp.
path = Path('app/lib/state/settings.dart')
text = path.read_text(encoding='utf-8')
count = text.count('minimumSize: const Size(0, 40),')
if count != 9:
    raise SystemExit(f'button minimum size: expected 9 matches, found {count}')
text = text.replace('minimumSize: const Size(0, 40),', 'minimumSize: const Size(0, 48),')
path.write_text(text, encoding='utf-8')

# Listing detail AppBar had explicit 40x44 controls, bypassing Material's normal
# 48dp tap target. Keep the compact visuals but restore accessible hit areas.
path = Path('app/lib/screens/listing_detail.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(text, '        toolbarHeight: 44,\n', '        toolbarHeight: 48,\n', 'detail toolbar height')
text = replace_once(text, '        leadingWidth: 40,\n', '        leadingWidth: 48,\n', 'detail leading width')
count = text.count('constraints: const BoxConstraints.tightFor(width: 40, height: 44),')
if count != 2:
    raise SystemExit(f'detail appbar constraints: expected 2 matches, found {count}')
text = text.replace(
    'constraints: const BoxConstraints.tightFor(width: 40, height: 44),',
    'constraints: const BoxConstraints.tightFor(width: 48, height: 48),',
)
path.write_text(text, encoding='utf-8')

# Regression coverage for localization grammar and theme-level tap target floor.
test = Path('app/test/accessibility_l10n_test.dart')
test.write_text("""import 'package:flat_finder/l10n/review_strings.dart';
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
""", encoding='utf-8')

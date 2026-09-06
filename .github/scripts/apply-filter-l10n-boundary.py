from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    return text.replace(old, new, 1)

# AppState filter mutation must not secretly launch transport. Callers decide
# whether a mutation needs a card search, map search, persistence only, etc.
path = Path('app/lib/state/app_state.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    """    final sortChanged = current.sort != normalized.sort;
    filters = normalized;
    notifyListeners();
    _saveFilters(); // persist so choices survive restarts

    // The header sort control only updates the filter. Server-backed sorts need
    // a fresh cursor stream (especially price asc/desc); scheduling here also
    // makes switching back from a server sort restore the canonical feed order.
    if (sortChanged) unawaited(search());
    return true;
""",
    """    filters = normalized;
    notifyListeners();
    _saveFilters(); // persist so choices survive restarts
    return true;
""",
    'pure updateFilters',
)
path.write_text(text, encoding='utf-8')

# Remaining feature-level copy used by Home/Map belongs to localization instead
# of language branches embedded in widgets.
path = Path('app/lib/l10n/review_strings.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    "  String get sortedTitle => _ru ? 'Отсортированные' : 'Sorted';\n",
    """  String get sortedTitle => _ru ? 'Отсортированные' : 'Sorted';
  String get reviewCollectionsMenu =>
      _ru ? 'Просмотреть подборки' : 'Review collections';
  String get loadingData => _ru ? 'Загружаем данные…' : 'Loading data…';
  String get placeWorkOnMap =>
      _ru ? 'Указать работу на карте' : 'Set work location on map';
  String get metresShort => _ru ? 'м' : 'm';
  String get kilometresShort => _ru ? 'км' : 'km';
""",
    'review/map l10n additions',
)
path.write_text(text, encoding='utf-8')

# Home: sort explicitly performs its requested network work and remaining menu
# / loading labels become localized.
path = Path('app/lib/screens/home_screen.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    """            onSelected: (v) =>
                state.updateFilters(state.filters.copyWith(sort: v)),
""",
    """            onSelected: (v) async {
              if (!state.updateFilters(state.filters.copyWith(sort: v))) return;
              await state.search();
              if (_mapMode) await state.loadMapListings();
            },
""",
    'explicit header sort search',
)
text = replace_once(
    text,
    """                const PopupMenuItem(
                    value: 'swipe',
                    child: ListTile(
                        leading: Icon(Icons.swipe),
                        title: Text('Просмотреть подборки'))),
                const PopupMenuItem(
                    value: 'sorted',
                    child: ListTile(
                        leading: Icon(Icons.done_all),
                        title: Text('Отсортированные'))),
""",
    """                PopupMenuItem(
                    value: 'swipe',
                    child: ListTile(
                        leading: const Icon(Icons.swipe),
                        title: Text(settings.s.reviewCollectionsMenu))),
                PopupMenuItem(
                    value: 'sorted',
                    child: ListTile(
                        leading: const Icon(Icons.done_all),
                        title: Text(settings.s.sortedTitle))),
""",
    'localized home menu',
)
text = replace_once(
    text,
    """                    child: _DataLoadingOverlay(
                      label: settings.lang == 'ru'
                          ? 'Загружаем данные…'
                          : 'Loading data…',
                    ),
""",
    """                    child: _DataLoadingOverlay(
                      label: settings.s.loadingData,
                    ),
""",
    'localized loading overlay',
)
path.write_text(text, encoding='utf-8')

# Map: localize the remaining work-radius controls and measurement abbreviations.
path = Path('app/lib/widgets/map_view.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    "import '../models/district_zone.dart';\n",
    "import '../l10n/review_strings.dart';\nimport '../models/district_zone.dart';\n",
    'map l10n extension import',
)
text = replace_once(
    text,
    "                  tooltip: 'Указать работу на карте',\n",
    "                  tooltip: s.placeWorkOnMap,\n",
    'map work tooltip',
)
text = replace_once(
    text,
    "                  Text('${(widget.radiusM! / 1000).toStringAsFixed(1)} км'),\n",
    "                  Text('${(widget.radiusM! / 1000).toStringAsFixed(1)} ${s.kilometresShort}'),\n",
    'map radius unit',
)
text = replace_once(
    text,
    "          Positioned(left: 12, bottom: 12, child: const _MetroLegend()),\n",
    "          Positioned(left: 12, bottom: 12, child: _MetroLegend(s: s)),\n",
    'localized metro legend invocation',
)
text = replace_once(
    text,
    """class _MetroLegend extends StatelessWidget {
  const _MetroLegend();

  @override
  Widget build(BuildContext context) {
""",
    """class _MetroLegend extends StatelessWidget {
  const _MetroLegend({required this.s});
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
""",
    'metro legend locale input',
)
text = replace_once(
    text,
    """      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LegendItem(color: _metro200Color, label: '200 м'),
          SizedBox(width: 8),
          _LegendItem(color: _metro500Color, label: '500 м'),
          SizedBox(width: 8),
          _LegendItem(color: _metro1000Color, label: '1 км'),
        ],
      ),
""",
    """      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LegendItem(color: _metro200Color, label: '200 ${s.metresShort}'),
          const SizedBox(width: 8),
          _LegendItem(color: _metro500Color, label: '500 ${s.metresShort}'),
          const SizedBox(width: 8),
          _LegendItem(color: _metro1000Color, label: '1 ${s.kilometresShort}'),
        ],
      ),
""",
    'localized metro legend units',
)
path.write_text(text, encoding='utf-8')

# ControlledApi exposes cancellation calls so we can prove updateFilters has no
# transport side effect without sleeping for the search debounce.
path = Path('app/test/state_correctness_test.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    """  ListingsResult? pageResult;

  @override
  Future<ListingsResult> fetchListings(
""",
    """  ListingsResult? pageResult;
  int cancellationCalls = 0;

  @override
  void cancelListingRequests() {
    cancellationCalls += 1;
    super.cancelListingRequests();
  }

  @override
  Future<ListingsResult> fetchListings(
""",
    'controlled api cancellation counter',
)
needle = """    test('set insertion order does not turn the same filters into a change', () {
      final state = AppState(ControlledApi());
      state.filters = Filters(
        countries: {'UZ'},
        sources: {'olx', 'telegram'},
        amenities: {'parking', 'balcony'},
      );

      final reordered = Filters(
        countries: {'UZ'},
        sources: {'telegram', 'olx'},
        amenities: {'balcony', 'parking'},
      );

      expect(state.updateFilters(reordered), isFalse);
    });
"""
addition = needle + """

    test('filter mutation is transport-free, including sort changes', () {
      final api = ControlledApi();
      final state = AppState(api)
        ..filters = Filters(countries: {'UZ'}, sort: SortBy.relevance);

      expect(
        state.updateFilters(state.filters.copyWith(sort: SortBy.priceAsc)),
        isTrue,
      );
      expect(state.filters.sort, SortBy.priceAsc);
      expect(api.cancellationCalls, 0);
    });
"""
text = replace_once(text, needle, addition, 'transport-free filter mutation test')
path.write_text(text, encoding='utf-8')

# L10n regression coverage for the remaining Home/Map chrome.
path = Path('app/test/accessibility_l10n_test.dart')
text = path.read_text(encoding='utf-8')
insert = """

  test('review and map chrome is localized outside widgets', () {
    const ru = AppStrings('ru');
    const en = AppStrings('en');
    expect(ru.reviewCollectionsMenu, 'Просмотреть подборки');
    expect(en.reviewCollectionsMenu, 'Review collections');
    expect(ru.loadingData, 'Загружаем данные…');
    expect(en.loadingData, 'Loading data…');
    expect(ru.placeWorkOnMap, 'Указать работу на карте');
    expect(en.placeWorkOnMap, 'Set work location on map');
    expect(ru.kilometresShort, 'км');
    expect(en.kilometresShort, 'km');
  });
"""
marker = "\n  test('primary button themes keep a 48dp minimum touch height', () {"
if marker not in text:
    raise SystemExit('accessibility l10n insertion marker not found')
text = text.replace(marker, insert + marker, 1)
path.write_text(text, encoding='utf-8')

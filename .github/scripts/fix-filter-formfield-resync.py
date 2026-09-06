from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, got {count}')
    return text.replace(old, new, 1)


path = Path('app/lib/widgets/filter_sheet.dart')
text = path.read_text()
text = replace_once(
    text,
    """                          DropdownButtonFormField<String?>(
                            initialValue: _metroBearingFrom == null ||
""",
    """                          DropdownButtonFormField<String?>(
                            key: ValueKey(
                              'filter-metro-direction-${_metroBearingFrom ?? 'any'}-${_metroBearingTo ?? 'any'}',
                            ),
                            initialValue: _metroBearingFrom == null ||
""",
    'metro direction key',
)
text = replace_once(
    text,
    """                        DropdownButtonFormField<String?>(
                          initialValue: _nearbyKind,
""",
    """                        DropdownButtonFormField<String?>(
                          key: ValueKey('filter-nearby-${_nearbyKind ?? 'any'}'),
                          initialValue: _nearbyKind,
""",
    'nearby key',
)
text = replace_once(
    text,
    """                          DropdownButtonFormField<String?>(
                            initialValue: _priceCurrency,
""",
    """                          DropdownButtonFormField<String?>(
                            key: ValueKey(
                              'filter-price-currency-${_priceCurrency ?? 'native'}',
                            ),
                            initialValue: _priceCurrency,
""",
    'price currency key',
)
text = replace_once(
    text,
    """                        DropdownButtonFormField<int?>(
                          initialValue: _maxAgeDays,
""",
    """                        DropdownButtonFormField<int?>(
                          key: ValueKey('filter-age-${_maxAgeDays ?? 'any'}'),
                          initialValue: _maxAgeDays,
""",
    'max age key',
)
text = replace_once(
    text,
    """                        DropdownButtonFormField<SortBy>(
                          initialValue: _sort,
""",
    """                        DropdownButtonFormField<SortBy>(
                          key: ValueKey('filter-sort-${_sort.name}'),
                          initialValue: _sort,
""",
    'sort key',
)
path.write_text(text)

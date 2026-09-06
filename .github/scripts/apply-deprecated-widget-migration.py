from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, got {count}')
    return text.replace(old, new, 1)


def patch(path: str, replacements: list[tuple[str, str, str]]) -> None:
    p = Path(path)
    text = p.read_text()
    for old, new, label in replacements:
        text = replace_once(text, old, new, label)
    p.write_text(text)


patch('app/lib/screens/home_screen.dart', [
    ("""                      child: DropdownButtonFormField<String>(
                        value: selectedCountry,
""", """                      child: DropdownButtonFormField<String>(
                        key: ValueKey('quick-country-$selectedCountry'),
                        initialValue: selectedCountry,
""", 'home country dropdown'),
    ("""                      child: DropdownButtonFormField<AgencyFilter>(
                        value: widget.filters.agency,
""", """                      child: DropdownButtonFormField<AgencyFilter>(
                        key: ValueKey(
                          'quick-agency-${widget.filters.agency.name}',
                        ),
                        initialValue: widget.filters.agency,
""", 'home agency dropdown'),
    ("""                      child: DropdownButtonFormField<_QuickDeal>(
                        value: _quickDealFor(widget.filters),
""", """                      child: DropdownButtonFormField<_QuickDeal>(
                        key: ValueKey(
                          'quick-deal-${_quickDealFor(widget.filters).name}',
                        ),
                        initialValue: _quickDealFor(widget.filters),
""", 'home deal dropdown'),
])

patch('app/lib/widgets/filter_sheet.dart', [
    ("""                        DropdownButtonFormField<String>(
                          value:
                              _countries.isNotEmpty ? _countries.first : null,
""", """                        DropdownButtonFormField<String>(
                          key: ValueKey(
                            'filter-country-${_countries.isNotEmpty ? _countries.first : ''}',
                          ),
                          initialValue:
                              _countries.isNotEmpty ? _countries.first : null,
""", 'filter country dropdown'),
    ("""                        DropdownButtonFormField<PropertyType>(
                          value: _type,
""", """                        DropdownButtonFormField<PropertyType>(
                          key: ValueKey('filter-type-${_type.name}'),
                          initialValue: _type,
""", 'filter type dropdown'),
    ("""                        DropdownButtonFormField<DealType>(
                          value: _deal,
""", """                        DropdownButtonFormField<DealType>(
                          key: ValueKey('filter-deal-${_deal.name}'),
                          initialValue: _deal,
""", 'filter deal dropdown'),
    ("""                        DropdownButtonFormField<AgencyFilter>(
                          value: _agency,
""", """                        DropdownButtonFormField<AgencyFilter>(
                          key: ValueKey('filter-agency-${_agency.name}'),
                          initialValue: _agency,
""", 'filter agency dropdown'),
    ("""                        DropdownButtonFormField<Audience>(
                          value: _audience,
""", """                        DropdownButtonFormField<Audience>(
                          key: ValueKey('filter-audience-${_audience.name}'),
                          initialValue: _audience,
""", 'filter audience dropdown'),
])

settings_path = Path('app/lib/screens/settings_screen.dart')
settings = settings_path.read_text()
settings = replace_once(
    settings,
    """          _sectionTitle(context, settings.t('theme')),
          ...kThemeOptions.map(
            (name) => RadioListTile<String>(
              value: name,
              groupValue: settings.themeName,
              title: Text(settings.t(_themeLabelKey(name))),
              secondary: Icon(_themeIcon(name)),
              onChanged: (v) => settings.setTheme(v!),
            ),
          ),
""",
    """          _sectionTitle(context, settings.t('theme')),
          RadioGroup<String>(
            groupValue: settings.themeName,
            onChanged: (value) {
              if (value != null) settings.setTheme(value);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final name in kThemeOptions)
                  RadioListTile<String>(
                    value: name,
                    title: Text(settings.t(_themeLabelKey(name))),
                    secondary: Icon(_themeIcon(name)),
                  ),
              ],
            ),
          ),
""",
    'theme RadioGroup',
)
settings = replace_once(
    settings,
    """          _sectionTitle(context, settings.t('language')),
          ...AppStrings.supported.map(
            (code) => RadioListTile<String>(
              value: code,
              groupValue: settings.lang,
              title: Text(AppStrings.languageNames[code] ?? code),
              onChanged: (v) => settings.setLang(v!),
            ),
          ),
""",
    """          _sectionTitle(context, settings.t('language')),
          RadioGroup<String>(
            groupValue: settings.lang,
            onChanged: (value) {
              if (value != null) settings.setLang(value);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final code in AppStrings.supported)
                  RadioListTile<String>(
                    value: code,
                    title: Text(AppStrings.languageNames[code] ?? code),
                  ),
              ],
            ),
          ),
""",
    'language RadioGroup',
)
settings = replace_once(
    settings,
    """          _sectionTitle(context, settings.t('displayCurrency')),
          ...SettingsState.currencyOptions.map(
            (cur) => RadioListTile<String?>(
              value: cur,
              groupValue: settings.displayCurrency,
              title: Text(cur ?? settings.t('nativeCurrency')),
              onChanged: (v) => settings.setDisplayCurrency(v),
            ),
          ),
""",
    """          _sectionTitle(context, settings.t('displayCurrency')),
          RadioGroup<String?>(
            groupValue: settings.displayCurrency,
            onChanged: settings.setDisplayCurrency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final cur in SettingsState.currencyOptions)
                  RadioListTile<String?>(
                    value: cur,
                    title: Text(cur ?? settings.t('nativeCurrency')),
                  ),
              ],
            ),
          ),
""",
    'currency RadioGroup',
)
settings_path.write_text(settings)

patch('app/lib/screens/listing_detail.dart', [
    ("""    _transform.value = Matrix4.identity()
      ..translate(-p.dx * 1.5, -p.dy * 1.5)
      ..scale(2.5);
""", """    _transform.value = Matrix4.identity()
      ..translateByDouble(-p.dx * 1.5, -p.dy * 1.5, 0, 1)
      ..scaleByDouble(2.5, 2.5, 2.5, 1);
""", 'Matrix4 explicit typed transforms'),
])

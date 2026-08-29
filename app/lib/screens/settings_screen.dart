import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../state/settings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    return Scaffold(
      appBar: AppBar(title: Text(settings.t('settings'))),
      body: ListView(
        children: [
          _sectionTitle(context, settings.t('theme')),
          ...kThemeOptions.map(
            (name) => RadioListTile<String>(
              value: name,
              groupValue: settings.themeName,
              title: Text(settings.t(_themeLabelKey(name))),
              secondary: Icon(_themeIcon(name)),
              onChanged: (v) => settings.setTheme(v!),
            ),
          ),
          const Divider(),
          _sectionTitle(context, settings.t('language')),
          ...AppStrings.supported.map(
            (code) => RadioListTile<String>(
              value: code,
              groupValue: settings.lang,
              title: Text(AppStrings.languageNames[code] ?? code),
              onChanged: (v) => settings.setLang(v!),
            ),
          ),
          const Divider(),
          _sectionTitle(context, settings.t('displayCurrency')),
          ...SettingsState.currencyOptions.map(
            (cur) => RadioListTile<String?>(
              value: cur,
              groupValue: settings.displayCurrency,
              title: Text(cur ?? settings.t('nativeCurrency')),
              onChanged: (v) => settings.setDisplayCurrency(v),
            ),
          ),
        ],
      ),
    );
  }

  String _themeLabelKey(String name) => switch (name) {
    'dark' => 'themeDark',
    'darkBlue' => 'themeDarkBlue',
    _ => 'themeLight',
  };

  IconData _themeIcon(String name) => switch (name) {
    'dark' => Icons.dark_mode_outlined,
    'darkBlue' => Icons.nightlight_outlined,
    _ => Icons.light_mode_outlined,
  };

  Widget _sectionTitle(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

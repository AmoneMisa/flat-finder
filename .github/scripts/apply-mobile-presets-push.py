from pathlib import Path


def read(path):
    return Path(path).read_text()


def write(path, text):
    Path(path).write_text(text)


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 anchor, got {count}')
    return text.replace(old, new, 1)


# backend app routes
path = 'backend/src/app.js'
s = read(path)
s = replace_once(
    s,
    "import {checkRate} from './request-rate-limit.js';\n",
    "import {checkRate} from './request-rate-limit.js';\nimport {registerMobileSubscriptionRoutes} from './mobile-subscriptions.js';\n",
    'app import',
)
s = replace_once(
    s,
    "  installMediaRoutes(app);\n\n  return app;",
    "  installMediaRoutes(app);\n  registerMobileSubscriptionRoutes(app);\n\n  return app;",
    'app route registration',
)
write(path, s)

# backend scanner lifecycle
path = 'backend/src/server.js'
s = read(path)
s = replace_once(
    s,
    "import {createApp} from './app.js';\n",
    "import {createApp} from './app.js';\nimport {startMobileSubscriptionScanner, stopMobileSubscriptionScanner} from './mobile-subscriptions.js';\n",
    'server import',
)
s = replace_once(
    s,
    "  const server = app.listen(PORT, () => {\n    console.log(`flat-finder backend listening on http://localhost:${PORT}`);\n    console.log(`countries: ${COUNTRY_CODES.join(', ')}`);\n  });",
    "  const server = app.listen(PORT, () => {\n    console.log(`flat-finder backend listening on http://localhost:${PORT}`);\n    console.log(`countries: ${COUNTRY_CODES.join(', ')}`);\n    startMobileSubscriptionScanner();\n  });",
    'server start scanner',
)
s = replace_once(
    s,
    "    server.close(async () => {\n      try {",
    "    stopMobileSubscriptionScanner();\n    server.close(async () => {\n      try {",
    'server stop scanner',
)
write(path, s)

# FCM: don't reference an Android channel the app has not explicitly created.
path = 'backend/src/mobile-fcm.js'
s = read(path)
s = replace_once(
    s,
    "          android: {\n            priority: 'high',\n            notification: {\n              channel_id: 'new_listings',\n              click_action: 'FLUTTER_NOTIFICATION_CLICK',\n            },\n          },",
    "          android: {priority: 'high'},",
    'fcm default channel',
)
write(path, s)

# sample env for server FCM credentials / cadence
path = 'backend/sample.env'
s = read(path)
if 'FIREBASE_SERVICE_ACCOUNT_B64=' not in s:
    s += "\n# Anonymous mobile apartment-preset push notifications. The service-account\n# JSON is base64 encoded so the credential stays in the deployment env only.\nFIREBASE_SERVICE_ACCOUNT_B64=\nMOBILE_SUBSCRIPTION_POLL_SECONDS=60\nMOBILE_SUBSCRIPTION_MAX_NOTIFICATIONS_PER_SCAN=8\n"
write(path, s)

# Flutter dependencies and actual header logo asset.
path = 'app/pubspec.yaml'
s = read(path)
s = replace_once(
    s,
    "  app_links: ^6.3.2\n",
    "  app_links: ^6.3.2\n  firebase_core: ^4.14.0\n  firebase_messaging: ^16.6.0\n",
    'flutter firebase deps',
)
s = replace_once(
    s,
    "  assets:\n    - assets/icon/icon.png\n",
    "  assets:\n    - assets/icon/icon.png\n    - assets/logo.png\n",
    'flutter logo asset',
)
write(path, s)

# Android 13+ notification permission.
path = 'app/android/app/src/main/AndroidManifest.xml'
s = read(path)
s = replace_once(
    s,
    '    <uses-permission android:name="android.permission.INTERNET"/>\n',
    '    <uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n',
    'android notification permission',
)
write(path, s)

# API method used only by PresetsState; all preset storage stays local.
path = 'app/lib/services/api_service.dart'
s = read(path)
anchor = """  Future<Map<String, double>> fetchRates() async {
    final res = await http.get(Uri.parse('$baseUrl/api/rates'));
    if (res.statusCode != 200) {
      throw Exception('rates HTTP ${res.statusCode}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final rates = (json['rates'] as Map<String, dynamic>? ?? {});
    return rates.map((k, v) => MapEntry(k, (v as num).toDouble()));
  }
}"""
replacement = """  Future<Map<String, double>> fetchRates() async {
    final res = await http.get(Uri.parse('$baseUrl/api/rates'));
    if (res.statusCode != 200) {
      throw Exception('rates HTTP ${res.statusCode}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final rates = (json['rates'] as Map<String, dynamic>? ?? {});
    return rates.map((k, v) => MapEntry(k, (v as num).toDouble()));
  }

  Future<void> syncMobileSubscriptions({
    required String deviceId,
    required String pushToken,
    required bool enabled,
    required String platform,
    required String language,
    required List<Map<String, dynamic>> presets,
  }) async {
    final res = await http
        .put(
          Uri.parse('$baseUrl/api/mobile-subscriptions'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({
            'deviceId': deviceId,
            'pushToken': pushToken,
            'enabled': enabled,
            'platform': platform,
            'language': language,
            'presets': presets,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('mobile subscriptions HTTP ${res.statusCode}');
    }
  }
}"""
s = replace_once(s, anchor, replacement, 'api mobile sync')
write(path, s)

# PresetsState API payload is a serializable snapshot, not Dart model objects.
path = 'app/lib/state/presets.dart'
s = read(path)
s = replace_once(
    s,
    '        presets: active,\n',
    "        presets: active.map((p) => p.toJson()).toList(),\n",
    'preset api payload',
)
write(path, s)

# Provider is eagerly initialized so a cold-start notification can be consumed.
path = 'app/lib/main.dart'
s = read(path)
s = replace_once(
    s,
    '        ChangeNotifierProvider(create: (_) => PresetsState()..load()),\n',
    '        ChangeNotifierProvider(\n          lazy: false,\n          create: (_) => PresetsState(ApiService())..load(),\n        ),\n',
    'presets provider',
)
write(path, s)

# Settings: global push switch + route to saved housing lists.
path = 'app/lib/screens/settings_screen.dart'
s = read(path)
s = replace_once(
    s,
    "import '../state/settings.dart';\n",
    "import '../state/settings.dart';\nimport '../state/presets.dart';\nimport 'presets_screen.dart';\n",
    'settings imports',
)
s = replace_once(
    s,
    "    final settings = context.watch<SettingsState>();\n    return Scaffold(",
    "    final settings = context.watch<SettingsState>();\n    final presets = context.watch<PresetsState>();\n    return Scaffold(",
    'settings state',
)
needle = """          const Divider(),
          _sectionTitle(context, settings.t('displayCurrency')),
"""
insert = """          const Divider(),
          _sectionTitle(context, settings.t('pushNotifications')),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: Text(settings.t('pushNotifications')),
            subtitle: Text(
              presets.pushClientConfigured
                  ? settings.t('pushNotificationsHint')
                  : settings.t('pushSetupRequired'),
            ),
            value: presets.pushMasterEnabled,
            onChanged: (value) async {
              final ok = await presets.setPushMasterEnabled(value);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(settings.t('pushEnableFailed'))),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add_check_circle_outlined),
            title: Text(settings.t('presetHousingTitle')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PresetsScreen()),
            ),
          ),
          const Divider(),
          _sectionTitle(context, settings.t('displayCurrency')),
"""
s = replace_once(s, needle, insert, 'settings push section')
write(path, s)

# Home: push-deep-link handling, presets entry, logo sizing/asset, quick filters.
path = 'app/lib/screens/home_screen.dart'
s = read(path)
s = replace_once(
    s,
    "import '../state/hidden.dart';\nimport '../state/settings.dart';\n",
    "import '../state/hidden.dart';\nimport '../state/settings.dart';\nimport '../services/push_service.dart';\n",
    'home push import',
)
s = replace_once(
    s,
    "import 'listing_detail.dart';\nimport 'settings_screen.dart';\n",
    "import 'listing_detail.dart';\nimport 'presets_screen.dart';\nimport 'settings_screen.dart';\n",
    'home presets import',
)
s = replace_once(
    s,
    "  StreamSubscription<Uri>? _linkSub;\n",
    "  StreamSubscription<Uri>? _linkSub;\n  StreamSubscription<int>? _pushListingSub;\n",
    'home push sub field',
)
s = replace_once(
    s,
    "    _initDeepLinks();\n    _resultsScroll.addListener(_loadMoreNearEnd);",
    "    _initDeepLinks();\n    _pushListingSub = PushService.instance.listingOpens.listen(_openSharedListing);\n    _resultsScroll.addListener(_loadMoreNearEnd);",
    'home push listener',
)
s = replace_once(
    s,
    "    _linkSub?.cancel();\n    _resultsScroll.dispose();",
    "    _linkSub?.cancel();\n    _pushListingSub?.cancel();\n    _resultsScroll.dispose();",
    'home push dispose',
)
s = replace_once(
    s,
    "  void _openHistory() {\n    Navigator.of(context)\n        .push(MaterialPageRoute(builder: (_) => const HistoryScreen()));\n  }\n",
    "  void _openHistory() {\n    Navigator.of(context)\n        .push(MaterialPageRoute(builder: (_) => const HistoryScreen()));\n  }\n\n  void _openPresets() {\n    Navigator.of(context)\n        .push(MaterialPageRoute(builder: (_) => const PresetsScreen()));\n  }\n",
    'home presets route',
)
s = replace_once(
    s,
    "        toolbarHeight: 52,\n        title: Image.asset(\n          'assets/logo.png',\n          height: 48,",
    "        toolbarHeight: 52,\n        titleSpacing: 8,\n        title: Image.asset(\n          'assets/logo.png',\n          height: 36,",
    'home logo',
)
s = replace_once(
    s,
    "                case 'favorites':\n                  _openFavorites();\n                case 'statistics':",
    "                case 'favorites':\n                  _openFavorites();\n                case 'presets':\n                  _openPresets();\n                case 'statistics':",
    'home presets menu action',
)
s = replace_once(
    s,
    "                PopupMenuItem(\n                  value: 'favorites',\n                  child: ListTile(\n                    leading: const Icon(Icons.favorite_border),\n                    title: Text(settings.t('favorites')),\n                  ),\n                ),\n                PopupMenuItem(\n                  value: 'settings',",
    "                PopupMenuItem(\n                  value: 'favorites',\n                  child: ListTile(\n                    leading: const Icon(Icons.favorite_border),\n                    title: Text(settings.t('favorites')),\n                  ),\n                ),\n                PopupMenuItem(\n                  value: 'presets',\n                  child: ListTile(\n                    leading: const Icon(Icons.playlist_add_check_circle_outlined),\n                    title: Text(settings.t('presetHousingTitle')),\n                  ),\n                ),\n                PopupMenuItem(\n                  value: 'settings',",
    'home presets menu item',
)
s = replace_once(
    s,
    "class _MobilePrimaryFiltersState extends State<_MobilePrimaryFilters> {\n  late final TextEditingController _query;",
    "class _MobilePrimaryFiltersState extends State<_MobilePrimaryFilters> {\n  bool _collapsed = false;\n  late final TextEditingController _query;",
    'quick filter collapsed state',
)
s = replace_once(
    s,
    "      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),\n      constraints: const BoxConstraints.tightFor(height: 42),",
    "      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),\n      constraints: const BoxConstraints.tightFor(height: 48),",
    'quick filter input height',
)
s = replace_once(
    s,
    "          child: Column(\n            children: [\n              TextField(\n                controller: _query,",
    "          child: Column(\n            children: [\n              if (!_collapsed) ...[\n              TextField(\n                controller: _query,",
    'quick filter collapse open',
)
end_anchor = """              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _priceMin,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: s.t('quickPriceMin'),
                        hintText: s.t('minPlaceholder'),
                      ),
                      onChanged: (_) => _schedule(_withTextValues()),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: TextField(
                      controller: _priceMax,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: s.t('quickPriceMax'),
                        hintText: s.t('maxPlaceholder'),
                      ),
                      onChanged: (_) => _schedule(_withTextValues()),
                    ),
                  ),
                ],
              ),
            ],
"""
end_replacement = end_anchor.replace(
    "              ),\n            ],\n",
    "              ),\n              ],\n              SizedBox(\n                height: 24,\n                child: IconButton(\n                  tooltip: s.t(_collapsed ? 'expandFilters' : 'collapseFilters'),\n                  padding: EdgeInsets.zero,\n                  constraints: const BoxConstraints.tightFor(width: 44, height: 24),\n                  visualDensity: VisualDensity.compact,\n                  onPressed: () => setState(() => _collapsed = !_collapsed),\n                  icon: Icon(\n                    _collapsed ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,\n                    size: 22,\n                  ),\n                ),\n              ),\n            ],\n",
    1,
)
s = replace_once(s, end_anchor, end_replacement, 'quick filter collapse close')
write(path, s)

# Listing card visual alignment.
path = 'app/lib/widgets/listing_card.dart'
s = read(path)
s = replace_once(
    s,
    "          SizedBox(height: compact ? 2 : 6),",
    "          SizedBox(height: compact ? 0 : 3),",
    'price gap',
)
s = replace_once(
    s,
    "    return Container(\n      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),\n      decoration: BoxDecoration(\n        color: BrandColors.toneGreen.withValues(alpha: 0.16),",
    "    return Container(\n      alignment: Alignment.center,\n      constraints: const BoxConstraints(minHeight: 22),\n      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),\n      decoration: BoxDecoration(\n        color: BrandColors.toneGreen.withValues(alpha: 0.16),",
    'good price badge align',
)
s = replace_once(
    s,
    "              fontSize: 10,\n              fontWeight: FontWeight.w700,\n            ),\n          ),\n        ],\n      ),\n    );\n  }\n}\n\nclass _WarningBadge",
    "              fontSize: 10,\n              height: 1,\n              fontWeight: FontWeight.w700,\n            ),\n          ),\n        ],\n      ),\n    );\n  }\n}\n\nclass _WarningBadge",
    'good price text align',
)
s = replace_once(
    s,
    "  Widget build(BuildContext context) => Container(\n        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),",
    "  Widget build(BuildContext context) => Container(\n        alignment: Alignment.center,\n        constraints: const BoxConstraints(minHeight: 22),\n        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),",
    'warning badge align',
)
# The warning style is the next matching orange text style.
s = replace_once(
    s,
    "                fontSize: 10,\n                fontWeight: FontWeight.w700,\n              ),\n            ),\n          ],\n        ),\n      );\n}\n\nclass _CardPhotoCarousel",
    "                fontSize: 10,\n                height: 1,\n                fontWeight: FontWeight.w700,\n              ),\n            ),\n          ],\n        ),\n      );\n}\n\nclass _CardPhotoCarousel",
    'warning text align',
)
s = replace_once(
    s,
    "    return Container(\n      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),\n      decoration: BoxDecoration(\n        color: const Color(0xFF0D1128),",
    "    return Container(\n      alignment: Alignment.center,\n      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),\n      decoration: BoxDecoration(\n        color: const Color(0xFF0D1128),",
    'deal badge align',
)
s = replace_once(
    s,
    "          color: color,\n          fontSize: 11,\n          fontWeight: FontWeight.w700,\n        ),\n      ),\n    );\n  }\n}\n\nclass _ViewedIcon",
    "          color: color,\n          fontSize: 11,\n          height: 1,\n          fontWeight: FontWeight.w700,\n        ),\n      ),\n    );\n  }\n}\n\nclass _ViewedIcon",
    'deal badge text align',
)
s = replace_once(
    s,
    "    return Container(\n      padding: EdgeInsets.symmetric(\n        horizontal: compact ? 5 : 7,",
    "    return Container(\n      alignment: Alignment.center,\n      padding: EdgeInsets.symmetric(\n        horizontal: compact ? 5 : 7,",
    'tag badge align',
)
s = replace_once(
    s,
    "          fontSize: compact ? 8.5 : 10.5,\n          fontWeight: FontWeight.w600,",
    "          fontSize: compact ? 8.5 : 10.5,\n          height: 1,\n          fontWeight: FontWeight.w600,",
    'tag badge text align',
)
write(path, s)

# Filter preset save now offers push immediately after saving.
path = 'app/lib/widgets/filter_sheet.dart'
s = read(path)
s = replace_once(
    s,
    "    if (name != null && name.isNotEmpty && mounted) {\n      await context.read<PresetsState>().save(name, _currentFilters());\n    }",
    "    if (name != null && name.isNotEmpty && mounted) {\n      final presets = context.read<PresetsState>();\n      final preset = await presets.save(name, _currentFilters());\n      if (preset == null || !mounted) return;\n      final enablePush = await showDialog<bool>(\n        context: context,\n        builder: (dialogCtx) => AlertDialog(\n          title: Text(s.t('enablePresetPushPromptTitle')),\n          content: Text(s.t('enablePresetPushPromptBody', {'name': preset.name})),\n          actions: [\n            TextButton(\n              onPressed: () => Navigator.pop(dialogCtx, false),\n              child: Text(s.t('notNow')),\n            ),\n            FilledButton.icon(\n              onPressed: () => Navigator.pop(dialogCtx, true),\n              icon: const Icon(Icons.notifications_active_outlined),\n              label: Text(s.t('enablePresetPush')),\n            ),\n          ],\n        ),\n      );\n      if (enablePush == true && mounted) {\n        final ok = await presets.setNotificationsEnabled(preset.id, true);\n        if (!ok && mounted) {\n          final key = presets.pushError == 'firebase_not_configured'\n              ? 'pushSetupRequired'\n              : 'pushEnableFailed';\n          ScaffoldMessenger.of(context).showSnackBar(\n            SnackBar(content: Text(s.t(key))),\n          );\n        }\n      }\n    }",
    'preset push prompt',
)
write(path, s)

# EN/RU strings for preset lists / push / collapse controls.
path = 'app/lib/l10n/strings.dart'
s = read(path)
s = replace_once(
    s,
    "      'presetUpdated': 'Preset updated',\n      'rename': 'Rename',",
    "      'presetUpdated': 'Preset updated',\n      'presetHousingTitle': 'Housing by filter presets',\n      'noPresets': 'No filter presets yet. Save one from Filters first.',\n      'allListingsPreset': 'All listings',\n      'pushNotifications': 'New-listing notifications',\n      'pushNotificationsHint': 'Notify this phone when enabled presets get new listings.',\n      'pushSetupRequired': 'Push transport is not configured in this app build yet.',\n      'pushEnableFailed': 'Could not enable notifications. Check notification permission and connection.',\n      'enablePresetPush': 'Enable notifications',\n      'disablePresetPush': 'Disable notifications',\n      'enablePresetPushPromptTitle': 'Notify about new listings?',\n      'enablePresetPushPromptBody': 'Turn on notifications for “{name}”?',\n      'notNow': 'Not now',\n      'collapseFilters': 'Collapse filters',\n      'expandFilters': 'Expand filters',\n      'rename': 'Rename',",
    'english push strings',
)
s = replace_once(
    s,
    "      'presetUpdated': 'Пресет обновлён',\n      'rename': 'Переименовать',",
    "      'presetUpdated': 'Пресет обновлён',\n      'presetHousingTitle': 'Жильё по пресету фильтров',\n      'noPresets': 'Пока нет пресетов фильтров. Сначала сохраните пресет в фильтрах.',\n      'allListingsPreset': 'Все объявления',\n      'pushNotifications': 'Уведомления о новых квартирах',\n      'pushNotificationsHint': 'Присылать на этот телефон новые объявления по включённым пресетам.',\n      'pushSetupRequired': 'Push ещё не настроен для этой сборки приложения.',\n      'pushEnableFailed': 'Не удалось включить уведомления. Проверьте разрешение и соединение.',\n      'enablePresetPush': 'Включить уведомления',\n      'disablePresetPush': 'Выключить уведомления',\n      'enablePresetPushPromptTitle': 'Уведомлять о новых квартирах?',\n      'enablePresetPushPromptBody': 'Включить уведомления для пресета «{name}»?',\n      'notNow': 'Не сейчас',\n      'collapseFilters': 'Свернуть фильтры',\n      'expandFilters': 'Развернуть фильтры',\n      'rename': 'Переименовать',",
    'russian push strings',
)
write(path, s)

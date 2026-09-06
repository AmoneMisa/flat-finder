import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'l10n/strings.dart';
import 'services/api_service.dart';
import 'state/app_state.dart';
import 'state/favorites.dart';
import 'state/hidden.dart';
import 'state/history.dart';
import 'state/presets.dart';
import 'state/settings.dart';
import 'state/sorted.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const FlatFinderApp());
}

/// Lets pointers other than touch (mouse, trackpad, stylus) drag scrollables,
/// so swiping the photo gallery works on Windows/web.
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

class FlatFinderApp extends StatelessWidget {
  const FlatFinderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // One transport instance per application. Apart from reusing connection
        // state this also lets startup prefetch, AppState and push subscriptions
        // share the same request policy instead of behaving like separate apps.
        Provider<ApiService>(create: (_) => ApiService()),
        ChangeNotifierProvider(create: (_) => SettingsState()..load()),
        ChangeNotifierProvider(
          create: (context) =>
              AppState(context.read<ApiService>())..init(),
        ),
        ChangeNotifierProvider(create: (_) => FavoritesState()..load()),
        ChangeNotifierProvider(create: (_) => HistoryState()..load()),
        ChangeNotifierProvider(create: (_) => HiddenState()..load()),
        ChangeNotifierProvider(
          lazy: false,
          create: (context) =>
              PresetsState(context.read<ApiService>())..load(),
        ),
        ChangeNotifierProvider(create: (_) => SortedState()..load()),
      ],
      child: Consumer<SettingsState>(
        builder: (context, settings, _) => MaterialApp(
          title: settings.t('appTitle'),
          debugShowCheckedModeBanner: false,
          locale: settings.locale,
          supportedLocales: AppStrings.supported.map((l) => Locale(l)),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: settings.themeData,
          // Allow drag-to-scroll with a mouse/trackpad (not just touch), so the
          // photo carousel and lists can be swiped on desktop/web too.
          scrollBehavior: const _AppScrollBehavior(),
          // Home owns deep links and update checks. Do not construct it until the
          // first feed request has actually settled: otherwise a cold-start deep
          // link races filter restoration and, visually, the empty initial model
          // briefly reads as a genuine "0 results" search.
          home: const _BootstrapGate(),
        ),
      ),
    );
  }
}

class _BootstrapGate extends StatefulWidget {
  const _BootstrapGate();

  @override
  State<_BootstrapGate> createState() => _BootstrapGateState();
}

class _BootstrapGateState extends State<_BootstrapGate> {
  bool _observedInitialSearch = false;
  bool _ready = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    // AppState starts with loading=false while it restores local filters and
    // fetches metadata. Remember the first real search transition, then release
    // the gate only after it settles. A valid zero-result response therefore
    // opens Home, while the pre-search empty model never masquerades as one.
    if (state.loading) _observedInitialSearch = true;
    if (!_ready &&
        (state.error != null ||
            state.listings.isNotEmpty ||
            (_observedInitialSearch && !state.loading))) {
      _ready = true;
    }

    if (_ready) return const HomeScreen();

    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Semantics(
            label: 'Flat Finder',
            liveRegion: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/icon/runtime.png',
                  width: 72,
                  height: 72,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.home_work_outlined,
                    size: 64,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

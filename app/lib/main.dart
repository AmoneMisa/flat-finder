import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'l10n/strings.dart';
import 'services/api_service.dart';
import 'state/app_state.dart';
import 'state/favorites.dart';
import 'state/history.dart';
import 'state/presets.dart';
import 'state/settings.dart';
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
        ChangeNotifierProvider(create: (_) => SettingsState()..load()),
        ChangeNotifierProvider(create: (_) => AppState(ApiService())..init()),
        ChangeNotifierProvider(create: (_) => FavoritesState()..load()),
        ChangeNotifierProvider(create: (_) => HistoryState()..load()),
        ChangeNotifierProvider(create: (_) => PresetsState()..load()),
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
          theme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: const Color(0xFF2E7D6B),
            brightness: Brightness.light,
          ),
          // Allow drag-to-scroll with a mouse/trackpad (not just touch), so the
          // photo carousel and lists can be swiped on desktop/web too.
          scrollBehavior: const _AppScrollBehavior(),
          home: const HomeScreen(),
        ),
      ),
    );
  }
}

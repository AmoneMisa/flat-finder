import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'l10n/strings.dart';
import 'services/api_service.dart';
import 'state/app_state.dart';
import 'state/settings.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const FlatFinderApp());
}

class FlatFinderApp extends StatelessWidget {
  const FlatFinderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsState()..load()),
        ChangeNotifierProvider(create: (_) => AppState(ApiService())..init()),
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
          home: const HomeScreen(),
        ),
      ),
    );
  }
}

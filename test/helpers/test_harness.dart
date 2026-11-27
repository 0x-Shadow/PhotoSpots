import 'package:flutter/material.dart';
import 'package:photospot/data/spot_repository.dart';
import 'package:photospot/state/app_state.dart';
import 'package:photospot/state/auth_state.dart';
import 'package:photospot/state/settings_state.dart';
import 'package:photospot/theme/app_theme.dart';
import 'package:provider/provider.dart';

/// The provider set `main.dart` installs, for tests that pump a screen directly.
///
/// One shared harness means a provider added to the app cannot reach production
/// while every test file silently keeps providing only the old set.
Widget testApp({
  required Widget home,
  SpotRepository? repository,
  AppState? appState,
  AuthState? authState,
  SettingsState? settingsState,
}) {
  return MultiProvider(
    providers: [
      if (settingsState != null)
        ChangeNotifierProvider.value(value: settingsState)
      else
        ChangeNotifierProvider(create: (_) => SettingsState()..load()),
      if (authState != null)
        ChangeNotifierProvider.value(value: authState)
      else
        ChangeNotifierProvider(create: (_) => AuthState()..load()),
      if (appState != null)
        ChangeNotifierProvider.value(value: appState)
      else
        ChangeNotifierProxyProvider2<AuthState, SettingsState, AppState>(
          create: (_) => AppState(repository ?? MockSpotRepository())..load(),
          update: (_, auth, settings, app) {
            final state =
                app ?? (AppState(repository ?? MockSpotRepository())..load());
            state.syncContext(
              activeUserId: auth.activeUserId,
              personalizeFeed: settings.personalizeFeed,
            );
            return state;
          },
        ),
    ],
    child: MaterialApp(theme: AppTheme.dark, home: home),
  );
}

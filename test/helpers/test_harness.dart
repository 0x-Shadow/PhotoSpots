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
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(
        value:
            appState ?? (AppState(repository ?? MockSpotRepository())..load()),
      ),
      ChangeNotifierProvider(create: (_) => SettingsState()..load()),
      ChangeNotifierProvider(create: (_) => AuthState()..load()),
    ],
    child: MaterialApp(theme: AppTheme.dark, home: home),
  );
}

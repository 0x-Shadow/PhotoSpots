import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photospot/data/spot_repository.dart';
import 'package:photospot/screens/profile_screen.dart';
import 'package:photospot/screens/settings_screen.dart';
import 'package:photospot/state/app_state.dart';
import 'package:photospot/state/settings_state.dart';
import 'package:photospot/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app({Widget home = const SettingsScreen()}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(
        create: (_) => AppState(MockSpotRepository())..load(),
      ),
      ChangeNotifierProvider(create: (_) => SettingsState()..load()),
    ],
    child: MaterialApp(theme: AppTheme.dark, home: home),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('the map style persists', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await tester.tap(find.text('Street'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SettingsState.mapStyleKey), 'street');
  });

  testWidgets('CARTO without a key stays disabled with an inline hint', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await tester.tap(find.text('CARTO dark'));
    await tester.pumpAndSettle();

    expect(
      find.text('Paste a CARTO API key to use this style.'),
      findsOneWidget,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SettingsState.mapStyleKey), isNull);
  });

  testWidgets('profile has one settings entry and no Preferences sheet', (
    tester,
  ) async {
    await tester.pumpWidget(_app(home: const ProfileScreen()));
    await tester.pump();

    expect(find.text('Preferences'), findsNothing);
    expect(find.bySemanticsLabel('Settings'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}

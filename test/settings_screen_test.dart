import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photospot/screens/profile_screen.dart';
import 'package:photospot/screens/settings_screen.dart';
import 'package:photospot/state/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/test_harness.dart';

Widget _app({Widget home = const SettingsScreen()}) =>
    testApp(home: home);

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

  testWidgets('profile reaches settings and has no Preferences sheet', (
    tester,
  ) async {
    await tester.pumpWidget(_app(home: const ProfileScreen()));
    await tester.pump();

    expect(find.text('Preferences'), findsNothing);
    final entry = find.byIcon(Icons.settings_rounded);
    expect(entry, findsOneWidget);

    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photospot/screens/profile_screen.dart';
import 'package:photospot/screens/settings_screen.dart';
import 'package:photospot/state/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/test_harness.dart';

Widget _app({Widget home = const SettingsScreen()}) => testApp(home: home);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('the map style persists', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    final street = find.text('Street');
    await tester.scrollUntilVisible(
      street,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(street);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SettingsState.mapStyleKey), 'street');
  });

  testWidgets('CARTO without a key stays disabled with an inline hint', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    final carto = find.text('CARTO dark');
    await tester.scrollUntilVisible(
      carto,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(carto);
    await tester.pumpAndSettle();

    expect(
      find.text('Paste a CARTO API key to use this style.'),
      findsOneWidget,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SettingsState.mapStyleKey), isNull);
  });

  testWidgets('guest settings expose an honest account state and legal docs', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.text('You’re browsing as a guest'), findsOneWidget);
    expect(find.text('Display name'), findsNothing);
    expect(find.text('Edit profile'), findsNothing);

    final privacy = find.text('Privacy Policy');
    await tester.scrollUntilVisible(
      privacy,
      280,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(privacy);
    await tester.pumpAndSettle();
    expect(find.text('How PhotoSpot handles your data'), findsOneWidget);
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

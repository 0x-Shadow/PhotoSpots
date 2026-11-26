import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photospot/data/spot_repository.dart';
import 'package:photospot/screens/root_shell.dart';
import 'package:photospot/state/app_state.dart';
import 'package:photospot/state/settings_state.dart';
import 'package:photospot/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app() {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(
        create: (_) => AppState(MockSpotRepository())..load(),
      ),
      ChangeNotifierProvider(create: (_) => SettingsState()..load()),
    ],
    child: MaterialApp(theme: AppTheme.dark, home: const RootShell()),
  );
}

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(_app());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('the add action is present on every tab', (tester) async {
    await _pumpApp(tester);
    expect(find.bySemanticsLabel('Add a spot'), findsOneWidget);

    for (final tab in ['Saved', 'Profile', 'Map', 'Home']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Add a spot'),
        findsOneWidget,
        reason: 'Add action vanished on $tab',
      );
    }
  });

  testWidgets('tapping add opens the submit flow', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.bySemanticsLabel('Add a spot'));
    await tester.pumpAndSettle();

    expect(find.text('Show the spot at its best'), findsOneWidget);
  });

  testWidgets('the selected tab exposes semantics', (tester) async {
    await _pumpApp(tester);

    final home = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label == 'Home' &&
          widget.properties.selected == true,
    );
    expect(home, findsOneWidget);
  });

  testWidgets('the wide rail also exposes the add action', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpApp(tester);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.bySemanticsLabel('Add a spot'), findsOneWidget);
  });
}

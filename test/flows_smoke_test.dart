import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photospot/data/spot_repository.dart';
import 'package:photospot/screens/root_shell.dart';
import 'package:photospot/state/app_state.dart';
import 'package:photospot/state/settings_state.dart';
import 'package:photospot/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _pop(WidgetTester tester) {
  tester.state<NavigatorState>(find.byType(Navigator).first).pop();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('detail, categories, submit, profile and plan flows lay out',
      (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AppState(MockSpotRepository())..load(),
          ),
          ChangeNotifierProvider(create: (_) => SettingsState()..load()),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const RootShell()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    // Categories.
    await tester.tap(find.text('See all').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Categories'), findsWidgets);
    expect(tester.takeException(), isNull);
    _pop(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // Spot detail via the trending hero.
    await tester.tap(find.byType(Hero).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Get Directions'), findsOneWidget);
    expect(tester.takeException(), isNull);
    _pop(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // Submit flow opens on the photo step.
    await tester.tap(find.byIcon(Icons.add_rounded).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Show the spot at its best'), findsOneWidget);
    expect(tester.takeException(), isNull);
    _pop(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // Profile and its sheets.
    await tester.tap(find.text('Profile').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('My Collections'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Preferences'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(8, 8));
    await tester.pump(const Duration(milliseconds: 400));

    // Plan trip screen.
    await tester.tap(find.text('My Collections'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Plan Your Trip'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

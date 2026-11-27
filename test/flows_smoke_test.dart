import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photospot/data/spot_repository.dart';
import 'package:photospot/screens/root_shell.dart';
import 'package:photospot/state/app_state.dart';
import 'package:photospot/state/settings_state.dart';
import 'package:photospot/theme/app_theme.dart';
import 'package:photospot/widgets/place_card.dart';
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

  testWidgets('detail, categories, submit, profile and plan flows lay out', (
    tester,
  ) async {
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
    await tester.scrollUntilVisible(
      find.text('See all').first,
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('See all').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Categories'), findsWidgets);
    expect(tester.takeException(), isNull);
    _pop(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // Spot detail via the trending hero (scroll back up to the carousel).
    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, 1400),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TrendingCard));
    await tester.pump();
    await tester.tap(find.byType(TrendingCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Get Directions'), findsOneWidget);
    expect(tester.takeException(), isNull);
    _pop(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // Submit flow opens on the photo step.
    await tester.tap(find.bySemanticsLabel('Add a spot'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Show the spot at its best'), findsOneWidget);
    expect(tester.takeException(), isNull);
    _pop(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // Profile and its settings screen.
    await tester.tap(find.text('Profile').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Plan a trip'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Settings'), findsWidgets);
    expect(tester.takeException(), isNull);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Plan trip screen.
    await tester.tap(find.text('Plan a trip'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Plan Your Trip'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

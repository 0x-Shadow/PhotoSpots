import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photospot/data/spot_repository.dart';
import 'package:photospot/screens/map_screen.dart';
import 'package:photospot/state/app_state.dart';
import 'package:photospot/state/settings_state.dart';
import 'package:photospot/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('share control appears only with a fix and can be tapped', (
    tester,
  ) async {
    final appState = AppState(MockSpotRepository());
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: appState),
          ChangeNotifierProvider(create: (_) => SettingsState()..load()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: MapScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.bySemanticsLabel('Share my location'), findsNothing);

    await appState.cacheFix(38.7223, -9.1335);
    await tester.pumpAndSettle();

    final share = find.bySemanticsLabel('Share my location');
    expect(share, findsOneWidget);

    await tester.tap(share);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

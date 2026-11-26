import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photospot/data/spot_repository.dart';
import 'package:photospot/screens/spot_detail_screen.dart';
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

  Future<void> pumpDetail(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AppState(MockSpotRepository())..load(),
          ),
          ChangeNotifierProvider(create: (_) => SettingsState()..load()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const SpotDetailScreen(spotId: 'senhora-monte'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('detail shows a mini map, sticky share and honest facts', (
    tester,
  ) async {
    await pumpDetail(tester);

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('Saves'), findsOneWidget);
    expect(find.text('Category'), findsOneWidget);
    expect(find.text('Best time'), findsOneWidget);
    expect(find.bySemanticsLabel('Share this spot'), findsWidgets);

    final bar = find.byKey(const ValueKey('sticky_bar'));
    expect(bar, findsOneWidget);
    expect(find.descendant(of: bar, matching: find.byIcon(Icons.arrow_back_rounded)),
        findsOneWidget);
    expect(
      find.descendant(of: bar, matching: find.byIcon(Icons.ios_share_rounded)),
      findsOneWidget,
    );
    expect(tester.widget<AnimatedOpacity>(bar).opacity, 0.0);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<AnimatedOpacity>(bar).opacity, 1.0);
    expect(tester.takeException(), isNull);
  });
}

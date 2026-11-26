import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:photospot/data/spot_repository.dart';
import 'package:photospot/screens/settings_screen.dart';
import 'package:photospot/screens/submit_screen.dart';
import 'package:photospot/map/tile_sources.dart';
import 'package:photospot/services/update_service.dart';
import 'package:photospot/state/app_state.dart';
import 'package:photospot/state/location_outcome.dart';
import 'package:photospot/state/settings_state.dart';
import 'package:photospot/theme/app_animations.dart';
import 'package:photospot/theme/app_theme.dart';
import 'package:photospot/widgets/location_prompt.dart';
import 'package:photospot/widgets/spot_mini_map.dart';
import 'package:photospot/widgets/update_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _withProviders(Widget home, {AppState? app}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(
        value: app ?? AppState(MockSpotRepository())..load(),
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

  testWidgets('a first-run pin says it is the demo area', (tester) async {
    await tester.pumpWidget(
      _withProviders(const Scaffold(body: SubmitScreen(initialStep: 1))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.text('No saved location yet — showing the demo area.'),
      findsOneWidget,
    );
  });

  testWidgets('a cached pin is not labelled as demo', (tester) async {
    SharedPreferences.setMockInitialValues({
      AppState.lastLatKey: 48.8566,
      AppState.lastLngKey: 2.3522,
    });
    final app = AppState(MockSpotRepository());
    await app.load();

    await tester.pumpWidget(
      _withProviders(const Scaffold(body: SubmitScreen(initialStep: 1)), app: app),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('No saved location yet — showing the demo area.'),
        findsNothing);
  });

  testWidgets('runLocationFlow publishes its outcome to app state', (
    tester,
  ) async {
    final app = AppState(MockSpotRepository());
    await tester.pumpWidget(
      _withProviders(const Scaffold(body: SizedBox.shrink()), app: app),
    );
    final context = tester.element(find.byType(Scaffold));

    final flow = runLocationFlow(
      context,
      explain: false,
      appState: app,
      request: () async => LocationOutcome.denied,
    );
    await tester.pumpAndSettle();

    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    final outcome = await flow;

    expect(outcome, LocationOutcome.denied);
    expect(app.lastLocationOutcome, LocationOutcome.denied);
  });

  testWidgets('Settings does not claim location is ready before any request', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_withProviders(const SettingsScreen()));
    await tester.pump();

    expect(find.text('Not requested yet'), findsOneWidget);
    expect(find.text('Ready'), findsNothing);
  });

  testWidgets('denied recovery offers a retry action', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );
    final context = tester.element(find.byType(Scaffold));
    var retried = false;

    final sheet = showLocationRecovery(
      context,
      LocationOutcome.denied,
      onRetry: () => retried = true,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(retried, isTrue);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    await sheet;
  });

  testWidgets('reduced motion skips pushed-route transitions', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    final context = tester.element(find.byType(Scaffold));
    final child = const SizedBox(key: ValueKey('page'));

    for (final route in [
      AppMotion.slideUp(child),
      AppMotion.slideUpModal(child),
    ]) {
      final builder = route.transitionsBuilder;
      expect(builder, isNotNull);
      final result = builder(
        context,
        const AlwaysStoppedAnimation(0),
        const AlwaysStoppedAnimation(0),
        child,
      );
      expect(identical(result, child), isTrue);
    }
  });

  testWidgets('mini-map falls back with a visible notice', (tester) async {
    await tester.pumpWidget(
      _withProviders(
        Scaffold(
          body: SpotMiniMap(
            point: const LatLng(38.7, -9.1),
            label: 'Open on map',
            probe: (_) async => TileProbeResult.failed,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Map unavailable'), findsOneWidget);
  });

  testWidgets('Settings release-page action opens the page', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );
    final context = tester.element(find.byType(Scaffold));
    Uri? opened;
    final release = ReleaseInfo(
      tag: 'v2.0.0',
      version: '2.0.0',
      notes: '',
      pageUrl: Uri.parse('https://example.com/release'),
    );

    await handleUpdateAction(
      context,
      release,
      UpdateAction.openPage,
      opener: (uri, _) async {
        opened = uri;
        return true;
      },
    );

    expect(opened, release.pageUrl);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:photospot/data/spot_repository.dart';
import 'package:photospot/state/app_state.dart';
import 'package:photospot/state/location_outcome.dart';
import 'package:photospot/widgets/location_prompt.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('classifyLocation', () {
    test('maps deniedForever to blocked and disabled services to servicesOff', () {
      expect(
        classifyLocation(servicesEnabled: false, deniedForever: false, denied: false),
        LocationOutcome.servicesOff,
      );
      expect(
        classifyLocation(servicesEnabled: true, deniedForever: true, denied: false),
        LocationOutcome.blocked,
      );
    });

    test('maps a plain denial to denied and success to granted', () {
      expect(
        classifyLocation(servicesEnabled: true, deniedForever: false, denied: true),
        LocationOutcome.denied,
      );
      expect(
        classifyLocation(servicesEnabled: true, deniedForever: false, denied: false),
        LocationOutcome.granted,
      );
      // Services off wins over a block, because no prompt can help there.
      expect(
        classifyLocation(servicesEnabled: false, deniedForever: true, denied: true),
        LocationOutcome.servicesOff,
      );
    });

    test('every outcome has user-facing copy', () {
      expect(locationMessage(LocationOutcome.granted), 'Location ready.');
      expect(
        locationMessage(LocationOutcome.servicesOff),
        'Location services are turned off.',
      );
      expect(
        locationMessage(LocationOutcome.blocked),
        'Location is blocked for PhotoSpot.',
      );
      expect(
        locationMessage(LocationOutcome.denied),
        'Location permission was denied.',
      );
      expect(
        locationMessage(LocationOutcome.failed),
        'Could not get your location right now.',
      );
    });
  });

  group('cached fix', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('requestLocation caches the fix for the next launch', () async {
      final first = AppState(MockSpotRepository());
      await first.cacheFix(38.7128, -9.1393);
      expect(first.hasCachedFix, isTrue);
      expect(first.referenceLocation, const LatLng(38.7128, -9.1393));

      final second = AppState(MockSpotRepository());
      await second.load();
      expect(second.hasCachedFix, isTrue);
      expect(second.referenceLocation, const LatLng(38.7128, -9.1393));
    });

    test('falls back to the demo seed when nothing is cached', () async {
      final state = AppState(MockSpotRepository());
      await state.load();
      expect(state.hasCachedFix, isFalse);
      expect(state.referenceLocation, AppState.fallbackCenter);
    });

    test('a live fix outranks the cached one', () async {
      final state = AppState(MockSpotRepository());
      await state.cacheFix(1.0, 2.0);
      await state.adoptLiveFix(48.8566, 2.3522);
      expect(state.referenceLocation, const LatLng(48.8566, 2.3522));
      expect(state.hasCachedFix, isTrue);
    });
  });

  group('rationale sheet', () {
    testWidgets('explains why location is needed and returns the choice', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      final context = tester.element(find.byType(Scaffold));

      final answer = showLocationRationale(context);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'PhotoSpot uses your location to sort spots by distance and '
          'centre the map on you.',
        ),
        findsOneWidget,
      );
      expect(find.text('Allow'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(await answer, isFalse);
    });
  });

  group('runLocationFlow', () {
    testWidgets('shows the rationale, then requests a fix', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      final context = tester.element(find.byType(Scaffold));

      var asked = 0;
      var requested = 0;
      final flow = runLocationFlow(
        context,
        needsRationale: () async {
          asked++;
          return true;
        },
        request: () async {
          requested++;
          return LocationOutcome.granted;
        },
      );
      await tester.pumpAndSettle();

      expect(asked, 1);
      expect(find.text('Allow'), findsOneWidget);
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();

      expect(requested, 1);
      expect(await flow, LocationOutcome.granted);
    });

    testWidgets('skips the rationale when asked and shows recovery for a '
        'blocked result', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      final context = tester.element(find.byType(Scaffold));

      var asked = 0;
      final flow = runLocationFlow(
        context,
        explain: false,
        needsRationale: () async {
          asked++;
          return true;
        },
        request: () async => LocationOutcome.blocked,
      );
      await tester.pumpAndSettle();

      expect(asked, 0);
      expect(find.text('Location is blocked for PhotoSpot.'), findsOneWidget);
      expect(find.text('Open settings'), findsOneWidget);

      Navigator.of(context).pop();
      await tester.pumpAndSettle();
      expect(await flow, LocationOutcome.blocked);
    });
  });

  group('recovery sheet', () {
    testWidgets('blocked outcome shows an Open settings action', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      final context = tester.element(find.byType(Scaffold));

      final sheet = showLocationRecovery(context, LocationOutcome.blocked);
      await tester.pumpAndSettle();

      expect(find.text('Location is blocked for PhotoSpot.'), findsOneWidget);
      expect(find.text('Open settings'), findsOneWidget);

      Navigator.of(context).pop();
      await tester.pumpAndSettle();
      await sheet;
    });

    testWidgets('services-off outcome explains and offers settings', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      final context = tester.element(find.byType(Scaffold));

      final sheet = showLocationRecovery(context, LocationOutcome.servicesOff);
      await tester.pumpAndSettle();

      expect(find.text('Location services are turned off.'), findsOneWidget);
      expect(find.text('Open settings'), findsOneWidget);

      Navigator.of(context).pop();
      await tester.pumpAndSettle();
      await sheet;
    });
  });
}

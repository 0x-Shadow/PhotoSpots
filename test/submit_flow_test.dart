import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:photospot/data/spot_repository.dart';
import 'package:photospot/screens/submit_screen.dart';
import 'package:photospot/state/app_state.dart';
import 'package:photospot/theme/app_theme.dart';
import 'package:photospot/widgets/spot_details_form.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('initial pin', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('prefers a cached fix over the demo seed', () async {
      SharedPreferences.setMockInitialValues({
        AppState.lastLatKey: 48.8566,
        AppState.lastLngKey: 2.3522,
      });
      final state = AppState(MockSpotRepository());
      await state.load();

      expect(
        SubmitScreen.initialPin(state),
        const LatLng(48.8566, 2.3522),
      );
    });

    test('uses the visible map centre when no fix is cached', () async {
      final state = AppState(MockSpotRepository());
      await state.load();
      expect(
        SubmitScreen.initialPin(state, mapCenter: const LatLng(41.0, -8.0)),
        const LatLng(41.0, -8.0),
      );
    });
  });

  testWidgets('publish is blocked without a name and explains why', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = SpotDraftController();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SpotDetailsForm(
            controller: controller,
            initialName: '',
            initialCity: '',
          ),
        ),
      ),
    );

    final publish = find.byKey(const ValueKey('details_publish'));
    expect(publish, findsOneWidget);
    await tester.tap(publish);
    await tester.pump();

    expect(
      find.text('Give the spot a name to publish.'),
      findsOneWidget,
    );
    expect(controller.canPublish, isFalse);
  });
}

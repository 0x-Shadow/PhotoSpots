import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:photospot/data/spot_repository.dart';
import 'package:photospot/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('load exposes seed spots', () async {
    final state = AppState(MockSpotRepository());
    await state.load();

    expect(state.loading, isFalse);
    expect(state.error, isNull);
    expect(state.spots, isNotEmpty);
    expect(state.rankedSpots.first.score,
        greaterThanOrEqualTo(state.rankedSpots.last.score));
  });

  test('saved ids persist locally across app starts', () async {
    final first = AppState(MockSpotRepository());
    await first.load();
    final spot = first.spots.first;

    expect(await first.toggleSave(spot), isTrue);
    expect(first.isSaved(spot.id), isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(AppState.savedIdsKey), contains(spot.id));

    final second = AppState(MockSpotRepository());
    await second.load();
    expect(second.isSaved(spot.id), isTrue);

    expect(await second.toggleSave(spot), isTrue);
    expect(second.isSaved(spot.id), isFalse);
    expect(
      (await SharedPreferences.getInstance())
          .getStringList(AppState.savedIdsKey),
      isNot(contains(spot.id)),
    );
  });

  test('submitting keeps the picked photo bytes', () async {
    final state = AppState(MockSpotRepository());
    await state.load();

    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final spot = await state.submitSpot(
      title: 'My rooftop',
      description: 'Quiet ledge with a river view.',
      location: const LatLng(38.71, -9.14),
      city: 'Lisbon',
      tags: const ['skyline', 'date'],
      bestTime: 'Golden hour',
      photoBytes: bytes,
    );

    expect(state.spotById(spot.id), isNotNull);
    expect(spot.coverPhoto.bytes, bytes);
    expect(state.spots.first.id, spot.id);
  });

  test('nearby is sorted by distance from the reference point', () async {
    final state = AppState(MockSpotRepository());
    await state.load();

    final spots = state.nearby(AppState.fallbackCenter);
    expect(spots, isNotEmpty);

    for (var i = 1; i < spots.length; i++) {
      final previous = state.distanceKm(
        AppState.fallbackCenter,
        spots[i - 1],
      );
      final current = state.distanceKm(AppState.fallbackCenter, spots[i]);
      expect(previous, lessThanOrEqualTo(current));
    }
  });
}

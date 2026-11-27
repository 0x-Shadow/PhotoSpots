import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:photospot/data/spot_repository.dart';
import 'package:photospot/models/comment.dart';
import 'package:photospot/models/spot.dart';
import 'package:photospot/services/apk_installer.dart';
import 'package:photospot/services/geocoding.dart';
import 'package:photospot/services/photo_compression.dart';
import 'package:photospot/state/app_state.dart';
import 'package:photospot/utils/ranking.dart';
import 'package:photospot/utils/solar.dart';
import 'package:photospot/utils/validators.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TrackingRepo extends MockSpotRepository {
  int fetchAllCalls = 0;
  int fetchSingleCalls = 0;

  @override
  Future<List<Spot>> fetchSpots() async {
    fetchAllCalls++;
    return super.fetchSpots();
  }

  @override
  Future<Spot?> fetchSpot(String spotId) async {
    fetchSingleCalls++;
    return super.fetchSpot(spotId);
  }

  @override
  Future<bool> toggleSave(Spot spot, {required bool saved}) async {
    await Future<void>.delayed(const Duration(milliseconds: 15));
    return super.toggleSave(spot, saved: saved);
  }

  @override
  Future<bool> toggleLike(Spot spot, {required bool liked}) async {
    await Future<void>.delayed(const Duration(milliseconds: 15));
    return super.toggleLike(spot, liked: liked);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('submittedById & production identity', () {
    test('submittedSpots matches activeUserId regardless of display name', () async {
      final repo = MockSpotRepository();
      final state = AppState(repo);
      await state.load();

      final customSpot = await repo.submitSpot(
        title: 'User Spot',
        description: 'View',
        location: const LatLng(38.71, -9.14),
        city: 'Lisbon',
        tags: const ['skyline'],
      );
      final remoteRow = customSpot.copyWith(
        submittedBy: 'Alice Photographer',
        submittedById: 'user-uuid-123',
      );
      final customRepo = _SingleListRepo([remoteRow]);
      final prodState = AppState(customRepo);
      prodState.syncContext(activeUserId: 'user-uuid-123', personalizeFeed: true);
      await prodState.load();

      expect(prodState.submittedSpots.map((s) => s.id), ['user-uuid-123'.isNotEmpty ? remoteRow.id : '']);
      expect(prodState.submittedSpots.single.submittedBy, 'Alice Photographer');
    });
  });

  group('concurrency & targeted refresh', () {
    test('concurrent toggleSave calls serialize and avoid full-table refetch', () async {
      final repo = _TrackingRepo();
      final state = AppState(repo);
      await state.load();
      final initialAll = repo.fetchAllCalls;
      final spot = state.spots.first;

      // Rapid double-tap (save then unsave) should settle deterministically.
      final f1 = state.toggleSave(spot);
      final f2 = state.toggleSave(spot);
      await Future.wait([f1, f2]);

      expect(state.isSaved(spot.id), isFalse);
      expect(repo.fetchAllCalls, initialAll);
      expect(repo.fetchSingleCalls, 2);
    });

    test('concurrent toggleLike calls serialize cleanly', () async {
      final repo = _TrackingRepo();
      final state = AppState(repo);
      await state.load();
      final spot = state.spots.first;
      final before = spot.likeCount;

      await Future.wait([
        state.toggleLike(spot),
        state.toggleLike(spot),
        state.toggleLike(spot),
      ]);

      expect(state.isLiked(spot.id), isTrue);
      expect(state.spotById(spot.id)!.likeCount, before + 1);
    });
  });

  group('algorithm & determinism', () {
    test('scoreAt(now) is deterministic for identical inputs', () {
      final now = DateTime(2026, 6, 1, 18, 30);
      final spot = Spot(
        id: 's1',
        title: 'Bridge Overlook',
        location: const LatLng(38.7, -9.1),
        photos: const [],
        rating: 4.9,
        reviewCount: 500,
        saveCount: 30,
        likeCount: 20,
        commentCount: 5,
        viewCount: 300,
        createdAt: now.subtract(const Duration(days: 3)),
      );
      expect(spot.scoreAt(now), equals(spot.scoreAt(now)));
    });

    test('Bayesian rating prevents 1-review 5.0 from beating 500-review 4.9', () {
      final now = DateTime(2026, 6, 1, 18, 30);
      final fluke = Spot(
        id: 'fluke',
        title: 'Fluke',
        location: const LatLng(38.7, -9.1),
        photos: const [],
        rating: 5.0,
        reviewCount: 1,
        createdAt: now,
      );
      final proven = Spot(
        id: 'proven',
        title: 'Proven',
        location: const LatLng(38.7, -9.1),
        photos: const [],
        rating: 4.9,
        reviewCount: 500,
        createdAt: now,
      );
      expect(proven.scoreAt(now), greaterThan(fluke.scoreAt(now)));
    });

    test('SpotRanking.recommend boosts current golden-hour & proximity spots', () {
      final goldenClock = DateTime(2026, 6, 1, 18, 30);
      final nearGolden = Spot(
        id: 'near-golden',
        title: 'Sunset Wall',
        location: const LatLng(38.713, -9.139),
        photos: const [],
        bestTime: 'Golden hour',
        tags: const ['sunset'],
        saveCount: 20,
        rating: 4.7,
        reviewCount: 50,
        createdAt: goldenClock,
      );
      final farMorning = Spot(
        id: 'far-morning',
        title: 'Distant Pier',
        location: const LatLng(41.15, -8.61),
        photos: const [],
        bestTime: 'Morning light',
        tags: const ['water'],
        saveCount: 20,
        rating: 4.7,
        reviewCount: 50,
        createdAt: goldenClock,
      );

      final ranked = SpotRanking.recommend(
        [farMorning, nearGolden],
        InterestProfile.empty,
        userLocation: const LatLng(38.7128, -9.1393),
        now: goldenClock,
      );
      expect(ranked.first.id, 'near-golden');
    });
  });

  group('privacy & moderation', () {
    test('stripJpegExif removes APP1 Exif segments while keeping SOS/EOI', () {
      // Minimal JPEG: SOI + APP1("Exif\0\0"...) + SOS + payload + EOI
      final fakeJpeg = Uint8List.fromList([
        0xFF, 0xD8, // SOI
        0xFF, 0xE1, 0x00, 0x0A, 0x45, 0x78, 0x69, 0x66, 0x00, 0x00, 0x11, 0x22, // APP1
        0xFF, 0xDA, 0x00, 0x04, 0xAA, 0xBB, // SOS
        0xFF, 0xD9, // EOI
      ]);

      final stripped = stripJpegExif(fakeJpeg);
      expect(stripped, equals(Uint8List.fromList([
        0xFF, 0xD8,
        0xFF, 0xDA, 0x00, 0x04, 0xAA, 0xBB,
        0xFF, 0xD9,
      ])));
    });

    test('blocking a user hides their spots and comments', () async {
      final repo = _SingleListRepo([
        const Spot(
          id: 's-bad',
          title: 'Spam Spot',
          location: LatLng(38.7, -9.1),
          photos: [],
          submittedBy: 'Spammer',
          submittedById: 'bad-user',
        ),
        const Spot(
          id: 's-good',
          title: 'Good Spot',
          location: LatLng(38.7, -9.1),
          photos: [],
          submittedBy: 'Good',
          submittedById: 'good-user',
        ),
      ], comments: [
        SpotComment(
          id: 'c1',
          spotId: 's-good',
          authorId: 'bad-user',
          authorName: 'Spammer',
          body: 'spam',
          createdAt: DateTime(2026, 1, 1),
        ),
        SpotComment(
          id: 'c2',
          spotId: 's-good',
          authorId: 'good-user',
          authorName: 'Good',
          body: 'nice light',
          createdAt: DateTime(2026, 1, 1),
        ),
      ]);

      final state = AppState(repo);
      await state.load();
      await state.loadComments('s-good');
      expect(state.spots.length, 2);
      expect(state.commentsFor('s-good').length, 2);

      await state.blockUser('bad-user');
      expect(state.spots.map((s) => s.id), ['s-good']);
      expect(state.commentsFor('s-good').map((c) => c.id), ['c2']);
    });

    test('Play Store build disables sideload APK installer by default', () {
      expect(ApkInstaller.isSupported, isFalse);
    });

    test('isSafeHttpsUrl blocks cleartext and non-http schemes', () {
      expect(Validators.isSafeHttpsUrl('https://example.com/a.jpg'), isTrue);
      expect(Validators.isSafeHttpsUrl('http://example.com/a.jpg'), isFalse);
      expect(Validators.isSafeHttpsUrl('javascript:alert(1)'), isFalse);
      expect(Validators.isSafeHttpsUrl('file:///etc/passwd'), isFalse);
      expect(Validators.isSafeHttpsUrl(''), isFalse);
    });

    test('hasAllowedImageMagicBytes accepts real headers and rejects fakes', () {
      expect(
        Validators.hasAllowedImageMagicBytes(
          Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0, 0, 0, 0]),
        ),
        isTrue,
      );
      expect(
        Validators.hasAllowedImageMagicBytes(
          Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0]),
        ),
        isTrue,
      );
      expect(
        Validators.hasAllowedImageMagicBytes(
          Uint8List.fromList(utf8.encode('<html><script>alert(1)</script></html>')),
        ),
        isFalse,
      );
    });

    test('geocoding drops out-of-range coordinates', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'features': [
              {
                'geometry': {
                  'coordinates': [999.0, 95.0],
                },
                'properties': {'name': 'Bogus', 'city': 'Nowhere'},
              },
              {
                'geometry': {
                  'coordinates': [-9.14, 38.71],
                },
                'properties': {'name': 'Lisbon Spot', 'city': 'Lisbon'},
              },
            ],
          }),
          200,
        );
      });
      final service = GeocodingService(client: client);
      final res = await service.searchPlaces('Lisbon');
      expect(res.results.length, 1);
      expect(res.results.single.city, 'Lisbon');
    });
  });

  group('solar, spot editing, multi-photo, and offline cache', () {
    test('SolarCalculator orders sunrise, golden hour, sunset, and blue hour', () {
      final light = SolarCalculator.forLocation(
        latitude: 38.7128,
        longitude: -9.1393,
        date: DateTime(2026, 6, 21),
      );
      expect(light.isPolarDay, isFalse);
      expect(light.isPolarNight, isFalse);
      expect(light.sunrise!.isBefore(light.morningGoldenEnd!), isTrue);
      expect(light.morningGoldenEnd!.isBefore(light.eveningGoldenStart!), isTrue);
      expect(light.eveningGoldenStart!.isBefore(light.sunset!), isTrue);
      expect(light.sunset!.isBefore(light.eveningBlueEnd!), isTrue);
    });

    test('updateSpot and addSpotPhoto mutate spot state cleanly', () async {
      final state = AppState(MockSpotRepository());
      await state.load();
      final spot = state.spots.first;
      final beforePhotos = spot.photos.length;

      final updated = await state.updateSpot(
        spotId: spot.id,
        title: 'Updated Viewpoint',
        description: 'Better tip',
        city: spot.city,
        tags: const ['skyline', 'sunset'],
        bestTime: 'Golden hour',
        focalLength: '35mm',
        tripodFriendly: true,
        accessNote: 'Free access',
      );
      expect(updated.title, 'Updated Viewpoint');
      expect(updated.focalLength, '35mm');
      expect(updated.tripodFriendly, isTrue);

      final fakeJpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0, 0, 0, 0]);
      await state.addSpotPhoto(spotId: spot.id, photoBytes: fakeJpeg);
      expect(state.spotById(spot.id)!.photos.length, beforePhotos + 1);
    });

    test('offline saved spots cache recovers saved spots when fetch fails', () async {
      final online = AppState(MockSpotRepository());
      await online.load();
      final target = online.spots.first;
      await online.toggleSave(target);

      final offline = AppState(_FailingRepo());
      await offline.load();
      expect(offline.error, isNull);
      expect(offline.isSaved(target.id), isTrue);
      expect(offline.savedSpots.map((s) => s.id), contains(target.id));
    });
  });
}

class _FailingRepo extends MockSpotRepository {
  @override
  Future<List<Spot>> fetchSpots() async => throw Exception('offline');
}

class _SingleListRepo extends MockSpotRepository {
  _SingleListRepo(this._customSpots, {this.comments = const []});

  final List<Spot> _customSpots;
  final List<SpotComment> comments;

  @override
  Future<List<Spot>> fetchSpots() async => List.unmodifiable(_customSpots);

  @override
  Future<List<SpotComment>> fetchComments(String spotId) async =>
      comments.where((c) => c.spotId == spotId).toList();
}

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:photospot/models/spot.dart';

Spot buildSpot({
  required String id,
  int saveCount = 0,
  int viewCount = 0,
  int ageDays = 0,
  List<SpotPhoto> photos = const [],
}) {
  return Spot(
    id: id,
    title: 'Spot $id',
    location: const LatLng(38.7, -9.1),
    photos: photos,
    saveCount: saveCount,
    viewCount: viewCount,
    createdAt: DateTime.now().subtract(Duration(days: ageDays)),
  );
}

void main() {
  group('ranking', () {
    test('saves outweigh a large view count', () {
      final viewed = buildSpot(id: 'a', saveCount: 10, viewCount: 5000);
      final saved = buildSpot(id: 'b', saveCount: 40, viewCount: 0);
      expect(saved.score, greaterThan(viewed.score));
    });

    test('view contribution is capped at 40 points', () {
      final low = buildSpot(id: 'a', saveCount: 10, viewCount: 100);
      final high = buildSpot(id: 'b', saveCount: 10, viewCount: 100000);
      // 0.05 points per view, clamped at 40 (lib/models/spot.dart).
      expect(high.score - low.score, lessThanOrEqualTo(40));
      // Even at the cap, a viral spot never beats a well-saved one.
      final saved = buildSpot(id: 'c', saveCount: 40);
      expect(saved.score, greaterThan(high.score));
    });

    test('fresh spots outrank older ones with the same saves', () {
      final fresh = buildSpot(id: 'a', saveCount: 10, ageDays: 0);
      final old = buildSpot(id: 'b', saveCount: 10, ageDays: 45);
      expect(fresh.score, greaterThan(old.score));
    });
  });

  group('photos', () {
    test('cover photo falls back to a placeholder', () {
      final spot = buildSpot(id: 'no-photos');
      expect(spot.photos, isEmpty);
      expect(spot.coverPhoto.url, contains('picsum.photos'));
      expect(spot.galleryPhotos, hasLength(1));
    });

    test('gallery includes every uploaded photo', () {
      final spot = buildSpot(
        id: 'with-photos',
        photos: const [
          SpotPhoto(id: '1', url: 'https://example.com/1.jpg'),
          SpotPhoto(id: '2', url: 'https://example.com/2.jpg'),
        ],
      );
      expect(spot.coverPhoto.url, 'https://example.com/1.jpg');
      expect(spot.galleryPhotos, hasLength(2));
    });
  });
}

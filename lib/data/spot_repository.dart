import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

import '../models/spot.dart';

/// A failure with a message that is safe to show to the user.
class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Contract every data source implements: mock today, Supabase when keys exist.
abstract class SpotRepository {
  Future<List<Spot>> fetchSpots();

  /// Saved spot IDs for the current user, or `null` when the source does not
  /// own save state (the app then falls back to local persistence).
  Future<Set<String>?> fetchSavedIds();

  /// Returns false when the save could not be persisted (e.g. no session).
  Future<bool> toggleSave(Spot spot, {required bool saved});

  Future<void> recordView(Spot spot);

  Future<Spot> submitSpot({
    required String title,
    required String description,
    required LatLng location,
    required String city,
    required List<String> tags,
    String? bestTime,
    Uint8List? photoBytes,
  });
}

/// In-memory repository with curated seed data. Powers the app until
/// Supabase credentials are configured.
class MockSpotRepository implements SpotRepository {
  final List<Spot> _spots = _seed();
  final Set<String> _savedIds = {};

  @override
  Future<List<Spot>> fetchSpots() async => List.unmodifiable(_spots);

  @override
  Future<Set<String>?> fetchSavedIds() async => null;

  @override
  Future<bool> toggleSave(Spot spot, {required bool saved}) async {
    final i = _spots.indexWhere((s) => s.id == spot.id);
    if (i != -1) {
      final current = _spots[i];
      final next = saved ? current.saveCount + 1 : current.saveCount - 1;
      _spots[i] = current.copyWith(saveCount: next < 0 ? 0 : next);
    }
    if (saved) {
      _savedIds.add(spot.id);
    } else {
      _savedIds.remove(spot.id);
    }
    return true;
  }

  @override
  Future<void> recordView(Spot spot) async {
    final i = _spots.indexWhere((s) => s.id == spot.id);
    if (i == -1) return;
    _spots[i] = _spots[i].copyWith(viewCount: _spots[i].viewCount + 1);
  }

  @override
  Future<Spot> submitSpot({
    required String title,
    required String description,
    required LatLng location,
    required String city,
    required List<String> tags,
    String? bestTime,
    Uint8List? photoBytes,
  }) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final spot = Spot(
      id: 'user-$stamp',
      title: title,
      description: description,
      location: location,
      city: city,
      tags: tags,
      bestTime: bestTime,
      createdAt: DateTime.now(),
      submittedBy: 'you',
      photos: [
        SpotPhoto(
          id: 'p-$stamp',
          // Demo mode has no storage bucket, so keep the picked bytes on the
          // photo and render them locally. Real uploads happen in
          // SupabaseSpotRepository.
          url: 'https://picsum.photos/seed/$title-$stamp/900/700',
          uploadedBy: 'you',
          takenAt: DateTime.now(),
          bytes: photoBytes,
        ),
      ],
    );
    _spots.insert(0, spot);
    return spot;
  }
}

/// Curated seed spots around Lisbon — a dense, photogenic test city.
List<Spot> _seed() {
  final now = DateTime.now();
  Spot spot(
    String id,
    String title,
    LatLng loc,
    String city,
    List<String> tags,
    String bestTime,
    String description,
    int saves,
    int views,
    int daysAgo, {
    String seed = '',
    double rating = 4.7,
    int reviews = 0,
  }) {
    final s = seed.isEmpty ? id : seed;
    return Spot(
      id: id,
      title: title,
      location: loc,
      city: city,
      tags: tags,
      bestTime: bestTime,
      description: description,
      rating: rating,
      reviewCount: reviews > 0 ? reviews : (saves * 17 + views ~/ 3),
      saveCount: saves,
      viewCount: views,
      createdAt: now.subtract(Duration(days: daysAgo)),
      submittedBy: 'PhotoSpot',
      photos: [
        SpotPhoto(
          id: '$id-1',
          url: 'https://picsum.photos/seed/$s-a/900/700',
          caption: '$title — hero shot',
          uploadedBy: 'PhotoSpot',
          takenAt: now.subtract(Duration(days: daysAgo + 3)),
        ),
        SpotPhoto(
          id: '$id-2',
          url: 'https://picsum.photos/seed/$s-b/900/700',
          caption: 'Alternate angle',
          uploadedBy: 'PhotoSpot',
          takenAt: now.subtract(Duration(days: daysAgo + 6)),
        ),
        SpotPhoto(
          id: '$id-3',
          url: 'https://picsum.photos/seed/$s-c/900/700',
          caption: 'Detail frame',
          uploadedBy: 'PhotoSpot',
          takenAt: now.subtract(Duration(days: daysAgo + 9)),
        ),
      ],
    );
  }

  return [
    spot(
      'senhora-monte',
      'Miradouro da Senhora do Monte',
      LatLng(38.7223, -9.1335),
      'Lisbon',
      ['skyline', 'sunset', 'date'],
      'Golden hour',
      'Highest viewpoint in Alfama. The whole city falls away toward the river — arrive 45 min before sunset and set up against the stone wall.',
      214, 1890, 2,
      rating: 4.9, reviews: 12500,
    ),
    spot(
      'santa-luzia',
      'Miradouro de Santa Luzia',
      LatLng(38.7121, -9.1305),
      'Lisbon',
      ['tiles', 'street', 'friends', 'date'],
      'Morning light',
      'Blue-and-white azulejo wall framed by bougainvillea. Best in soft morning light before the tour groups arrive.',
      168, 1420, 6,
      rating: 4.8, reviews: 8400,
    ),
    spot(
      'praca-comercio',
      'Praça do Comércio',
      LatLng(38.7077, -9.1365),
      'Lisbon',
      ['architecture', 'symmetry', 'date', 'friends'],
      'Blue hour',
      'Symmetrical arch and riverside square. Stand under Rua Augusta Arch to frame the whole plaza.',
      192, 1675, 4,
      rating: 4.9, reviews: 21000,
    ),
    spot(
      'belem-tower',
      'Belém Tower',
      LatLng(38.6916, -9.2160),
      'Lisbon',
      ['landmark', 'water', 'date'],
      'Sunset',
      'Shoot from the far side of the water for the full silhouette. Low tide exposes reflective sand.',
      143, 1210, 11,
      rating: 4.7, reviews: 15600,
    ),
    spot(
      'lx-factory',
      'LX Factory',
      LatLng(38.7033, -9.1786),
      'Lisbon',
      ['street', 'industrial', 'friends'],
      'Afternoon',
      'Industrial chic under the 25 de Abril bridge — murals, neon signs, and gritty textures.',
      97, 860, 9,
      rating: 4.6, reviews: 5200,
    ),
    spot(
      'trama-28',
      'Tram 28 at Graça',
      LatLng(38.7169, -9.1332),
      'Lisbon',
      ['street', 'tram', 'friends'],
      'Golden hour',
      'The classic yellow tram shot. Stand on the pavement bend and wait for the tram to crest the hill.',
      176, 1530, 1,
      rating: 4.8, reviews: 9800,
    ),
    spot(
      'castelo',
      'Castelo de São Jorge',
      LatLng(38.7139, -9.1335),
      'Lisbon',
      ['skyline', 'landmark', 'date'],
      'Sunset',
      'Ramparts look straight down over the red rooftops. Golden hour hits the castle walls first.',
      131, 1105, 15,
      rating: 4.7, reviews: 13400,
    ),
    spot(
      'augusta-arch',
      'Rua Augusta Arch',
      LatLng(38.7101, -9.1394),
      'Lisbon',
      ['architecture', 'symmetry'],
      'Blue hour',
      'Perfect one-point perspective down Rua Augusta. Tripod recommended after dark.',
      88, 790, 21,
      rating: 4.6, reviews: 6100,
    ),
    spot(
      'pink-street',
      'Pink Street',
      LatLng(38.7075, -9.1458),
      'Lisbon',
      ['street', 'nightlife', 'friends'],
      'Night',
      'Pink cobbles and yellow umbrellas. Empty and clean at dawn, buzzing with neon after dark.',
      120, 1015, 3,
      rating: 4.5, reviews: 7300,
    ),
    spot(
      'santa-justa',
      'Elevador de Santa Justa',
      LatLng(38.7121, -9.1390),
      'Lisbon',
      ['architecture', 'iron'],
      'Blue hour',
      'Gothic iron lift against the rooftops. Shoot from the upper terrace, not the street below.',
      74, 640, 27,
      rating: 4.4, reviews: 4900,
    ),
    spot(
      'cais-colunas',
      'Cais das Colunas',
      LatLng(38.7066, -9.1440),
      'Lisbon',
      ['water', 'reflection', 'date'],
      'Blue hour',
      'Two marble columns walking into the Tagus. Reflections pool around your feet at high tide.',
      102, 895, 7,
      rating: 4.7, reviews: 3800,
    ),
    spot(
      'graca-rooftops',
      'Graça Rooftop Ledge',
      LatLng(38.7185, -9.1347),
      'Lisbon',
      ['skyline', 'hidden gem', 'date'],
      'Golden hour',
      'A quiet residential ledge most tourists walk past. Full river view with no one behind you.',
      58, 430, 0,
      rating: 4.9, reviews: 1200,
    ),
  ];
}

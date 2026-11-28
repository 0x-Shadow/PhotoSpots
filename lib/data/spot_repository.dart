import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

import '../models/comment.dart';
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

  /// Geo-scoped, paginated spot fetch for large catalogs. Defaults to [fetchSpots]
  /// for in-memory repositories.
  Future<List<Spot>> fetchSpotsNear({
    required double lat,
    required double lng,
    double radiusKm = 50,
    int limit = 100,
    int offset = 0,
  }) =>
      fetchSpots();

  /// Refreshes a single spot by id when available, or returns `null`.
  Future<Spot?> fetchSpot(String spotId) async {
    final all = await fetchSpots();
    for (final s in all) {
      if (s.id == spotId) return s;
    }
    return null;
  }

  /// Saved spot IDs for the current user, or `null` when the source does not
  /// own save state (the app then falls back to local persistence).
  Future<Set<String>?> fetchSavedIds();

  /// Returns false when the save could not be persisted (e.g. no session).
  Future<bool> toggleSave(Spot spot, {required bool saved});

  /// Liked spot IDs for the current user, or `null` when the source does not
  /// own like state.
  Future<Set<String>?> fetchLikedIds();

  /// Returns false when the like could not be persisted.
  Future<bool> toggleLike(Spot spot, {required bool liked});

  Future<void> recordView(Spot spot);

  /// Newest comments first.
  Future<List<SpotComment>> fetchComments(String spotId);

  /// Adds a comment as the signed-in user and returns the stored row.
  Future<SpotComment> addComment({required String spotId, required String body});

  /// Deletes a comment owned by the current user.
  Future<void> deleteComment(String commentId) async {}

  /// Deletes a spot owned by the current user.
  Future<void> deleteSpot(String spotId) async {}

  /// Reports inappropriate content for moderation review (Google Play UGC).
  Future<void> reportContent({
    required String targetType,
    required String targetId,
    required String reason,
    String? details,
  }) async {}

  /// Asks the backend to un-hide content of [userId] that reports hid.
  /// The security-definer RPC only succeeds for the real owner and applies a
  /// per-week cooldown; returns false when the action is unavailable.
  Future<bool> appealHiddenSpot(String spotId) async => false;

  /// Blocks or unblocks another user's content.
  Future<Set<String>?> fetchBlockedUserIds() async => null;
  Future<void> blockUser(String userId) async {}
  Future<void> unblockUser(String userId) async {}

  Future<Spot> submitSpot({
    required String title,
    required String description,
    required LatLng location,
    required String city,
    required List<String> tags,
    String? bestTime,
    String? focalLength,
    bool? tripodFriendly,
    String? accessNote,
    Uint8List? photoBytes,
  });

  /// Updates mutable metadata on a spot owned by the active user.
  Future<Spot> updateSpot({
    required String spotId,
    required String title,
    required String description,
    required String city,
    required List<String> tags,
    String? bestTime,
    String? focalLength,
    bool? tripodFriendly,
    String? accessNote,
  }) async {
    throw const AppException('Editing spots is unavailable.');
  }

  /// Contributes an additional photo to an existing spot.
  Future<SpotPhoto> addSpotPhoto({
    required String spotId,
    required Uint8List photoBytes,
    String? caption,
  }) async {
    throw const AppException('Adding photos is unavailable.');
  }

  /// True when this source pushes live community changes (Supabase Realtime).
  /// In-memory sources return false so the UI never claims to be live.
  bool get supportsRealtime => false;

  /// Subscribes to live changes on spots, photos and comments. Returns a
  /// disposer; the default source has nothing to watch.
  void Function() subscribeToChanges({
    required void Function() onSpotsChanged,
    required void Function(String spotId) onCommentsChanged,
  }) =>
      () {};
}

/// In-memory repository with curated seed data. Powers the app until
/// Supabase credentials are configured.
class MockSpotRepository implements SpotRepository {
  MockSpotRepository() {
    _comments.addAll(_seedComments(_spots));
    // Keep the badge honest: the count is the number of comments we can show.
    for (var i = 0; i < _spots.length; i++) {
      final count =
          _comments.where((c) => c.spotId == _spots[i].id).length;
      if (count > 0) {
        _spots[i] = _spots[i].copyWith(commentCount: count);
      }
    }
  }

  final List<Spot> _spots = _seed();
  final Set<String> _savedIds = {};
  final Set<String> _likedIds = {};
  final List<SpotComment> _comments = [];

  /// Comments written in this session are attributed to the local person.
  String get _viewerName => 'You';

  /// Demo data lives in memory, so there is nothing to subscribe to.
  @override
  bool get supportsRealtime => false;

  @override
  void Function() subscribeToChanges({
    required void Function() onSpotsChanged,
    required void Function(String spotId) onCommentsChanged,
  }) =>
      () {};

  @override
  Future<List<Spot>> fetchSpots() async => List.unmodifiable(_spots);

  @override
  Future<List<Spot>> fetchSpotsNear({
    required double lat,
    required double lng,
    double radiusKm = 50,
    int limit = 100,
    int offset = 0,
  }) =>
      fetchSpots();

  @override
  Future<Set<String>?> fetchSavedIds() async => null;

  @override
  Future<Set<String>?> fetchLikedIds() async => null;

  @override
  Future<bool> toggleLike(Spot spot, {required bool liked}) async {
    final i = _spots.indexWhere((s) => s.id == spot.id);
    if (i != -1) {
      final current = _spots[i];
      final next = liked ? current.likeCount + 1 : current.likeCount - 1;
      _spots[i] = current.copyWith(likeCount: next < 0 ? 0 : next);
    }
    if (liked) {
      _likedIds.add(spot.id);
    } else {
      _likedIds.remove(spot.id);
    }
    return true;
  }

  @override
  Future<List<SpotComment>> fetchComments(String spotId) async =>
      _comments.where((comment) => comment.spotId == spotId).toList();

  @override
  Future<SpotComment> addComment({
    required String spotId,
    required String body,
  }) async {
    final comment = SpotComment(
      id: 'c-${DateTime.now().microsecondsSinceEpoch}',
      spotId: spotId,
      authorId: 'local-you',
      authorName: _viewerName,
      body: body,
      createdAt: DateTime.now(),
    );
    _comments.insert(0, comment);
    final i = _spots.indexWhere((s) => s.id == spotId);
    if (i != -1) {
      _spots[i] = _spots[i].copyWith(
        commentCount: _spots[i].commentCount + 1,
      );
    }
    return comment;
  }

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
  Future<Spot?> fetchSpot(String spotId) async {
    for (final s in _spots) {
      if (s.id == spotId) return s;
    }
    return null;
  }

  @override
  Future<void> deleteComment(String commentId) async {
    final idx = _comments.indexWhere((c) => c.id == commentId);
    if (idx == -1) return;
    final removed = _comments.removeAt(idx);
    final spotIdx = _spots.indexWhere((s) => s.id == removed.spotId);
    if (spotIdx != -1) {
      final next = _spots[spotIdx].commentCount - 1;
      _spots[spotIdx] = _spots[spotIdx].copyWith(
        commentCount: next < 0 ? 0 : next,
      );
    }
  }

  @override
  Future<void> deleteSpot(String spotId) async {
    _spots.removeWhere((s) => s.id == spotId);
    _comments.removeWhere((c) => c.spotId == spotId);
    _savedIds.remove(spotId);
    _likedIds.remove(spotId);
  }

  @override
  Future<void> reportContent({
    required String targetType,
    required String targetId,
    required String reason,
    String? details,
  }) async {}

  @override
  Future<bool> appealHiddenSpot(String spotId) async => false;

  @override
  Future<Set<String>?> fetchBlockedUserIds() async => null;

  @override
  Future<void> blockUser(String userId) async {}

  @override
  Future<void> unblockUser(String userId) async {}

  @override
  Future<Spot> submitSpot({
    required String title,
    required String description,
    required LatLng location,
    required String city,
    required List<String> tags,
    String? bestTime,
    String? focalLength,
    bool? tripodFriendly,
    String? accessNote,
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
      focalLength: focalLength,
      tripodFriendly: tripodFriendly,
      accessNote: accessNote,
      createdAt: DateTime.now(),
      submittedBy: 'You',
      submittedById: 'you',
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

  @override
  Future<Spot> updateSpot({
    required String spotId,
    required String title,
    required String description,
    required String city,
    required List<String> tags,
    String? bestTime,
    String? focalLength,
    bool? tripodFriendly,
    String? accessNote,
  }) async {
    final idx = _spots.indexWhere((s) => s.id == spotId);
    if (idx == -1) throw const AppException('Spot not found.');
    final updated = _spots[idx].copyWith(
      title: title,
      description: description,
      city: city,
      tags: tags,
      bestTime: bestTime,
      focalLength: focalLength,
      tripodFriendly: tripodFriendly,
      accessNote: accessNote,
    );
    _spots[idx] = updated;
    return updated;
  }

  @override
  Future<SpotPhoto> addSpotPhoto({
    required String spotId,
    required Uint8List photoBytes,
    String? caption,
  }) async {
    final idx = _spots.indexWhere((s) => s.id == spotId);
    if (idx == -1) throw const AppException('Spot not found.');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final photo = SpotPhoto(
      id: 'p-$stamp',
      url: 'https://picsum.photos/seed/$spotId-$stamp/900/700',
      caption: caption,
      uploadedBy: 'You',
      takenAt: DateTime.now(),
      bytes: photoBytes,
    );
    _spots[idx] = _spots[idx].copyWith(
      photos: [..._spots[idx].photos, photo],
    );
    return photo;
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
      // Seed engagement keeps the ranking and the comment section realistic
      // in demo mode without pretending to have real users.
      likeCount: (saves * 0.6).round(),
      commentCount: 0,
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

/// A few believable comments so the section is never empty in demo mode.
List<SpotComment> _seedComments(List<Spot> spots) {
  final now = DateTime.now();
  final seeds = <String, List<(String, String, int)>>{
    'senhora-monte': [
      ('Mara', 'Got here 50 minutes before sunset and the wall was free. Bring a jacket, it gets windy.', 0),
      ('Tomás', 'Best skyline in the city. Use the low wall as a natural tripod.', 1),
      ('Iris', 'Crowded by 19:00 in summer. Go early and shoot the west side.', 3),
    ],
    'santa-luzia': [
      ('Nuno', 'The azulejo wall is in shade until about 09:30 — that is the soft light you want.', 2),
      ('Ana', 'Bougainvillea was blooming in May. Perfect for portraits.', 5),
    ],
    'praca-comercio': [
      ('Leo', 'Stand under the arch at blue hour and wait for the lamps to come on.', 1),
      ('Sofia', 'Wide lens needed. The square is bigger than it looks.', 4),
    ],
    'trama-28': [
      ('Rui', 'Tram comes every 8 minutes or so. Pre-focus and burst.', 0),
      ('Bea', 'Morning is quieter and the light hits the yellow tram from the side.', 6),
    ],
    'graca-rooftops': [
      ('Inês', 'Nobody here at sunrise. My favourite spot in Lisbon.', 1),
    ],
  };

  final comments = <SpotComment>[];
  var index = 0;
  for (final spot in spots) {
    final entries = seeds[spot.id];
    if (entries == null) continue;
    for (final (author, body, hoursAgo) in entries) {
      comments.add(
        SpotComment(
          id: 'seed-${spot.id}-${index++}',
          spotId: spot.id,
          authorId: 'seed-$author',
          authorName: author,
          body: body,
          createdAt: now.subtract(Duration(hours: hoursAgo + 1)),
        ),
      );
    }
  }
  return comments;
}

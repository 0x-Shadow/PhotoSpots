import 'dart:typed_data';

import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/spot.dart';
import 'spot_repository.dart';

/// Supabase-backed repository. Used when SUPABASE_URL and SUPABASE_ANON_KEY
/// are configured in lib/main.dart.
///
/// The app has no login screen, so writes use an anonymous Supabase session.
/// Enable "Anonymous sign-ins" in Authentication → Providers for this to work.
class SupabaseSpotRepository implements SpotRepository {
  SupabaseSpotRepository();

  SupabaseClient get _client => Supabase.instance.client;

  Future<String?>? _sessionFuture;
  final Set<String> _profiledIds = {};

  /// The profile join must be named explicitly: `spots` and `profiles` are
  /// linked both by submitted_by and through saves, so an unqualified
  /// `profiles(...)` embed fails with PGRST201 (ambiguous relationship).
  static const _spotSelect = '''
    *,
    photos (*),
    profiles!spots_submitted_by_fkey (display_name, avatar_url)
  ''';

  /// Returns a user id, creating an anonymous session on first write.
  Future<String?> _ensureUserId() async {
    final userId =
        _client.auth.currentUser?.id ??
        await (_sessionFuture ??= _signInAnonymously());
    if (userId == null) return null;
    await _ensureProfile(userId);
    return userId;
  }

  /// Every write references profiles (spots.submitted_by, photos.uploader,
  /// saves.user_id, spot_views.viewer), but the on_auth_user_created trigger
  /// does not reliably fire for anonymous sessions. Without the row, inserts
  /// fail with a foreign key violation, so create it from the client.
  Future<void> _ensureProfile(String userId) async {
    if (!_profiledIds.add(userId)) return;
    try {
      await _client
          .from('profiles')
          .upsert(
            {'id': userId, 'display_name': 'Explorer'},
            onConflict: 'id',
            ignoreDuplicates: true,
          );
    } catch (_) {
      // Not fatal for reads, and a retry is cheap: drop the cache entry so the
      // next write tries again.
      _profiledIds.remove(userId);
    }
  }

  Future<String?> _signInAnonymously() async {
    try {
      final response = await _client.auth.signInAnonymously();
      return response.user?.id;
    } catch (_) {
      // Anonymous sign-in may be disabled; existing sessions still work.
      return _client.auth.currentUser?.id;
    } finally {
      _sessionFuture = null;
    }
  }

  @override
  Future<List<Spot>> fetchSpots() async {
    final response = await _client
        .from('spots')
        .select(_spotSelect)
        .order('created_at', ascending: false);

    return (response as List)
        .map((row) => _spotFromRow(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  @override
  Future<Set<String>?> fetchSavedIds() async {
    final userId = _client.auth.currentUser?.id;
    // No session yet: let the app keep its locally persisted saves.
    if (userId == null) return null;

    final response = await _client
        .from('saves')
        .select('spot_id')
        .eq('user_id', userId);

    return (response as List)
        .map((row) => row['spot_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  @override
  Future<bool> toggleSave(Spot spot, {required bool saved}) async {
    final userId = await _ensureUserId();
    if (userId == null) return false;

    if (saved) {
      await _client.from('saves').upsert({
        'user_id': userId,
        'spot_id': spot.id,
      }, onConflict: 'user_id,spot_id');
    } else {
      await _client
          .from('saves')
          .delete()
          .eq('user_id', userId)
          .eq('spot_id', spot.id);
    }
    return true;
  }

  @override
  Future<void> recordView(Spot spot) async {
    final userId = _client.auth.currentUser?.id;
    await _client.from('spot_views').insert({
      'spot_id': spot.id,
      'viewer': userId,
    });
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
    final userId = await _ensureUserId();
    if (userId == null) {
      throw const AppException(
        'Publishing needs a Supabase session. Enable anonymous sign-ins for '
        'this project, then try again.',
      );
    }

    // Upload first so a storage failure cannot leave a duplicate spot behind.
    String? photoUrl;
    if (photoBytes != null && photoBytes.isNotEmpty) {
      photoUrl = await uploadPhoto(bytes: photoBytes, userId: userId);
    }

    final response = await _client
        .from('spots')
        .insert({
          'title': title,
          'description': description,
          'city': city,
          'latitude': location.latitude,
          'longitude': location.longitude,
          'tags': tags,
          'best_time': bestTime,
          'submitted_by': userId,
        })
        .select()
        .single();

    final spotId = response['id'] as String;

    if (photoUrl != null) {
      await _client.from('photos').insert({
        'spot_id': spotId,
        'uploader': userId,
        'image_url': photoUrl,
        'taken_at': DateTime.now().toIso8601String(),
      });
    }

    final created = await _client
        .from('spots')
        .select(_spotSelect)
        .eq('id', spotId)
        .single();

    return _spotFromRow(Map<String, dynamic>.from(created as Map));
  }

  /// Uploads raw image bytes (works on mobile and web) and returns a public URL.
  Future<String> uploadPhoto({
    required Uint8List bytes,
    required String userId,
  }) async {
    final fileName =
        'spots/$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _client.storage
        .from('photos')
        .uploadBinary(
          fileName,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    return _client.storage.from('photos').getPublicUrl(fileName);
  }

  Spot _spotFromRow(Map<String, dynamic> row) {
    final rawPhotos = (row['photos'] as List?) ?? const [];
    final photos = rawPhotos
        .map((p) => Map<String, dynamic>.from(p as Map))
        .map(
          (p) => SpotPhoto(
            id: p['id']?.toString() ?? '',
            url: p['image_url']?.toString() ?? '',
            caption: p['caption'] as String?,
            uploadedBy: p['uploader']?.toString(),
            takenAt: p['taken_at'] != null
                ? DateTime.tryParse(p['taken_at'].toString())
                : null,
          ),
        )
        .where((photo) => photo.url.isNotEmpty)
        .toList();

    final profile = row['profiles'] == null
        ? null
        : Map<String, dynamic>.from(row['profiles'] as Map);

    return Spot(
      id: row['id']?.toString() ?? '',
      title: row['title'] as String? ?? '',
      location: LatLng(
        (row['latitude'] as num?)?.toDouble() ?? 0,
        (row['longitude'] as num?)?.toDouble() ?? 0,
      ),
      description: row['description'] as String? ?? '',
      city: row['city'] as String? ?? '',
      tags: (row['tags'] as List<dynamic>? ?? const [])
          .map((tag) => tag.toString())
          .toList(),
      bestTime: row['best_time'] as String?,
      rating: (row['rating'] as num?)?.toDouble() ?? 4.5,
      reviewCount: (row['review_count'] as num?)?.toInt() ?? 0,
      photos: photos,
      saveCount: (row['save_count'] as num?)?.toInt() ?? 0,
      viewCount: (row['view_count'] as num?)?.toInt() ?? 0,
      createdAt: row['created_at'] != null
          ? DateTime.tryParse(row['created_at'].toString())
          : null,
      submittedBy: profile?['display_name'] as String?,
    );
  }
}

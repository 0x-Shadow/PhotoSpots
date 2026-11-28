import 'dart:typed_data';

import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/comment.dart';
import '../models/spot.dart';
import '../utils/validators.dart';
import '../services/photo_format.dart';
import 'spot_repository.dart';

/// Supabase-backed repository. Used when SUPABASE_URL and SUPABASE_ANON_KEY
/// are configured in lib/main.dart.
///
/// Accounts & restrictions:
///  * Reading spots and comments is public.
///  * Publishing spots, commenting, liking, saving to the cloud, reporting, and
///    blocking require a real signed-in account (anonymous sessions are not
///    auto-created for writes, preventing throwaway spam).
class SupabaseSpotRepository implements SpotRepository {
  SupabaseSpotRepository();

  SupabaseClient get _client => Supabase.instance.client;

  final Set<String> _profiledIds = {};

  RealtimeChannel? _changesChannel;

  @override
  bool get supportsRealtime => true;

  /// Live community data. Spots, photos, likes/saves (server counters on the
  /// spot row) and comments all arrive here, so ranking, counts and open
  /// comment threads update without a manual refresh.
  @override
  void Function() subscribeToChanges({
    required void Function() onSpotsChanged,
    required void Function(String spotId) onCommentsChanged,
  }) {
    _changesChannel?.unsubscribe();
    final channel = _client
        .channel('public:photospot-feed')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'spots',
          callback: (_) => onSpotsChanged(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'photos',
          callback: (_) => onSpotsChanged(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'comments',
          callback: (payload) {
            final record = payload.newRecord.isNotEmpty
                ? payload.newRecord
                : payload.oldRecord;
            final spotId = record['spot_id']?.toString();
            if (spotId != null && spotId.isNotEmpty) {
              onCommentsChanged(spotId);
            }
          },
        );
    channel.subscribe();
    _changesChannel = channel;

    return () {
      if (_changesChannel == channel) _changesChannel = null;
      channel.unsubscribe();
      _client.removeChannel(channel);
    };
  }

  /// The profile join must be named explicitly: `spots` and `profiles` are
  /// linked both by submitted_by and through saves, so an unqualified
  /// `profiles(...)` embed fails with PGRST201 (ambiguous relationship).
  ///
  /// Photos are listed without `uploader`: the raw UUID is never needed by the
  /// UI (own photos are labelled "You" at insert time) and shipping every
  /// uploader id would let clients correlate a person's photos forever.
  static const _spotSelect = '''
    *,
    photos (id, spot_id, image_url, caption, taken_at),
    profiles!spots_submitted_by_fkey (display_name, avatar_url)
  ''';

  /// Returns the active non-anonymous user id, or `null` for guests.
  String? get _signedInUserId {
    final user = _client.auth.currentUser;
    if (user == null || user.isAnonymous) return null;
    return user.id;
  }

  /// Ensures a profile row exists for the signed-in user before writes.
  Future<String?> _requireAccountId() async {
    final userId = _signedInUserId;
    if (userId == null) return null;
    await _ensureProfile(userId);
    return userId;
  }

  /// Every write references profiles (spots.submitted_by, photos.uploader,
  /// saves.user_id, spot_views.viewer). Ensure the row exists for this user.
  Future<void> _ensureProfile(String userId) async {
    if (!_profiledIds.add(userId)) return;
    try {
      final metadataName =
          _client.auth.currentUser?.userMetadata?['display_name'];
      final name = (metadataName is String && metadataName.trim().isNotEmpty)
          ? metadataName.trim()
          : 'Explorer';
      await _client
          .from('profiles')
          .upsert(
            {'id': userId, 'display_name': name},
            onConflict: 'id',
            ignoreDuplicates: true,
          );
    } catch (_) {
      // Not fatal for reads, and a retry is cheap: drop the cache entry so the
      // next write tries again.
      _profiledIds.remove(userId);
    }
  }

  /// Upper bound for the initial feed pull. Large deployments should page
  /// (this order/limit pair is the app's whole read for now), but 300 silently
  /// starved the map of older spots, so the feed reads a wider window.
  static const _feedSpotLimit = 1000;

  @override
  Future<List<Spot>> fetchSpots() async {
    final response = await _client
        .from('spots')
        .select(_spotSelect)
        .order('created_at', ascending: false)
        .limit(_feedSpotLimit);

    return (response as List)
        .map((row) => _spotFromRow(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  @override
  Future<List<Spot>> fetchSpotsNear({
    required double lat,
    required double lng,
    double radiusKm = 50,
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      final idsResp = await _client.rpc(
        'nearby_spots',
        params: {
          'p_lat': lat,
          'p_lng': lng,
          'p_radius_km': radiusKm,
          'p_limit': limit,
          'p_offset': offset,
        },
      );
      final ids = (idsResp as List)
          .map((row) => (row as Map)['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      if (ids.isEmpty) return const [];
      final rows = await _client
          .from('spots')
          .select(_spotSelect)
          .inFilter('id', ids);
      final byId = <String, Spot>{
        for (final row in rows as List)
          if (row is Map)
            (row['id']?.toString() ?? ''): _spotFromRow(
              Map<String, dynamic>.from(row),
            ),
      };
      return [for (final id in ids) ?byId[id]];
    } catch (_) {
      // Fallback if the project has not run the latest nearby_spots migration.
      return fetchSpots();
    }
  }

  @override
  Future<Spot?> fetchSpot(String spotId) async {
    final response = await _client
        .from('spots')
        .select(_spotSelect)
        .eq('id', spotId)
        .maybeSingle();
    if (response == null) return null;
    return _spotFromRow(Map<String, dynamic>.from(response));
  }

  @override
  Future<Set<String>?> fetchSavedIds() async {
    final userId = _signedInUserId;
    // Guest: keep local saves on this device.
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
  Future<Set<String>?> fetchLikedIds() async {
    final userId = _signedInUserId;
    if (userId == null) return null;

    final response = await _client
        .from('likes')
        .select('spot_id')
        .eq('user_id', userId);

    return (response as List)
        .map((row) => row['spot_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  @override
  Future<bool> toggleLike(Spot spot, {required bool liked}) async {
    final userId = await _requireAccountId();
    if (userId == null) return false;

    if (liked) {
      await _client.from('likes').upsert({
        'user_id': userId,
        'spot_id': spot.id,
      }, onConflict: 'user_id,spot_id');
    } else {
      await _client
          .from('likes')
          .delete()
          .eq('user_id', userId)
          .eq('spot_id', spot.id);
    }
    return true;
  }

  /// The author join is named explicitly for the same reason as [_spotSelect]:
  /// profiles and comments are linked only by comments.author, but an
  /// unqualified embed can still be rejected when the relationship is not
  /// unique from PostgREST's point of view.
  static const _commentSelect = '''
    id,
    spot_id,
    author,
    body,
    created_at,
    profiles!comments_author_fkey (display_name)
  ''';

  @override
  Future<List<SpotComment>> fetchComments(String spotId) async {
    final response = await _client
        .from('comments')
        .select(_commentSelect)
        .eq('spot_id', spotId)
        .order('created_at', ascending: false)
        .limit(200);

    return (response as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .map(_commentFromRow)
        .toList();
  }

  @override
  Future<SpotComment> addComment({
    required String spotId,
    required String body,
  }) async {
    final userId = await _requireAccountId();
    if (userId == null) {
      throw const AppException(
        'Sign in with an account to join the conversation.',
      );
    }

    final response = await _client
        .from('comments')
        .insert({
          'spot_id': spotId,
          'author': userId,
          'body': body,
        })
        .select(_commentSelect)
        .single();

    return _commentFromRow(Map<String, dynamic>.from(response as Map));
  }

  @override
  Future<void> deleteComment(String commentId) async {
    final userId = _signedInUserId;
    if (userId == null) {
      throw const AppException('Sign in to delete your comment.');
    }
    await _client
        .from('comments')
        .delete()
        .eq('id', commentId)
        .eq('author', userId);
  }

  @override
  Future<void> deleteSpot(String spotId) async {
    final userId = _signedInUserId;
    if (userId == null) {
      throw const AppException('Sign in to delete your spot.');
    }
    await _client
        .from('spots')
        .delete()
        .eq('id', spotId)
        .eq('submitted_by', userId);
  }

  @override
  Future<void> reportContent({
    required String targetType,
    required String targetId,
    required String reason,
    String? details,
  }) async {
    final userId = await _requireAccountId();
    if (userId == null) {
      throw const AppException('Sign in to submit a report.');
    }
    await _client.from('reports').insert({
      'reporter_id': userId,
      'target_type': targetType,
      'target_id': targetId,
      'reason': reason,
      if (details != null && details.trim().isNotEmpty)
        'details': details.trim(),
    });
  }

  @override
  Future<bool> appealHiddenSpot(String spotId) async {
    try {
      await _client.rpc('appeal_hidden_content', params: {
        'p_target_type': 'spot',
        'p_target_id': spotId,
      });
      return true;
    } catch (_) {
      // Not hidden, cooldown active, or an older schema without the RPC.
      return false;
    }
  }

  @override
  Future<Set<String>?> fetchBlockedUserIds() async {
    final userId = _signedInUserId;
    if (userId == null) return null;
    try {
      final response = await _client
          .from('blocked_users')
          .select('blocked_id')
          .eq('blocker_id', userId);
      return (response as List)
          .map((row) => row['blocked_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> blockUser(String blockedUserId) async {
    final userId = await _requireAccountId();
    if (userId == null || blockedUserId == userId) return;
    await _client.from('blocked_users').upsert({
      'blocker_id': userId,
      'blocked_id': blockedUserId,
    }, onConflict: 'blocker_id,blocked_id');
  }

  @override
  Future<void> unblockUser(String blockedUserId) async {
    final userId = _signedInUserId;
    if (userId == null) return;
    await _client
        .from('blocked_users')
        .delete()
        .eq('blocker_id', userId)
        .eq('blocked_id', blockedUserId);
  }

  SpotComment _commentFromRow(Map<String, dynamic> row) {
    final profile = row['profiles'] == null
        ? null
        : Map<String, dynamic>.from(row['profiles'] as Map);
    final name = profile?['display_name'] as String?;

    return SpotComment(
      id: row['id']?.toString() ?? '',
      spotId: row['spot_id']?.toString() ?? '',
      authorId: row['author']?.toString() ?? '',
      authorName: (name == null || name.trim().isEmpty) ? 'Explorer' : name,
      body: row['body'] as String? ?? '',
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  @override
  Future<bool> toggleSave(Spot spot, {required bool saved}) async {
    final userId = await _requireAccountId();
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
    final userId = await _requireAccountId();
    if (userId == null) return;
    // One row per signed-in viewer per spot: prevents anonymous account spam
    // from inflating view counts in ranking.
    await _client.from('spot_views').upsert(
      {'spot_id': spot.id, 'viewer': userId},
      onConflict: 'spot_id,viewer',
      ignoreDuplicates: true,
    );
  }

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
    final userId = await _requireAccountId();
    if (userId == null) {
      throw const AppException(
        'Sign in with an account to publish spots.',
      );
    }

    final cleanTags = tags
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty && t.length <= 32)
        .take(12)
        .toList();

    // Upload first so a storage failure cannot leave a duplicate spot behind.
    String? photoUrl;
    if (photoBytes != null && photoBytes.isNotEmpty) {
      photoUrl = await uploadPhoto(bytes: photoBytes, userId: userId);
    }

    final response = await _client
        .from('spots')
        .insert({
          'title': title.trim(),
          'description': description.trim(),
          'city': city.trim(),
          'latitude': location.latitude,
          'longitude': location.longitude,
          'tags': cleanTags,
          'best_time': bestTime,
          if (focalLength != null && focalLength.trim().isNotEmpty)
            'focal_length': focalLength.trim(),
          'tripod_friendly': ?tripodFriendly,
          if (accessNote != null && accessNote.trim().isNotEmpty)
            'access_note': accessNote.trim(),
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
    final userId = _signedInUserId;
    if (userId == null) {
      throw const AppException('Sign in to edit your spot.');
    }
    final cleanTags = tags
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty && t.length <= 32)
        .take(12)
        .toList();

    final updated = await _client
        .from('spots')
        .update({
          'title': title.trim(),
          'description': description.trim(),
          'city': city.trim(),
          'tags': cleanTags,
          'best_time': bestTime,
          'focal_length':
              (focalLength == null || focalLength.trim().isEmpty)
                  ? null
                  : focalLength.trim(),
          'tripod_friendly': tripodFriendly,
          'access_note':
              (accessNote == null || accessNote.trim().isEmpty)
                  ? null
                  : accessNote.trim(),
        })
        .eq('id', spotId)
        .eq('submitted_by', userId)
        .select(_spotSelect)
        .single();

    return _spotFromRow(Map<String, dynamic>.from(updated as Map));
  }

  @override
  Future<SpotPhoto> addSpotPhoto({
    required String spotId,
    required Uint8List photoBytes,
    String? caption,
  }) async {
    final userId = await _requireAccountId();
    if (userId == null) {
      throw const AppException('Sign in to add a photo.');
    }
    final photoUrl = await uploadPhoto(bytes: photoBytes, userId: userId);
    final is360 = PhotoFormat.is360Equirectangular(photoBytes);
    final row = await _client
        .from('photos')
        .insert({
          'spot_id': spotId,
          'uploader': userId,
          'image_url': photoUrl,
          'is360': is360,
          if (caption != null && caption.trim().isNotEmpty)
            'caption': caption.trim(),
          'taken_at': DateTime.now().toIso8601String(),
        })
        .select()
        .single();

    return SpotPhoto(
      id: row['id']?.toString() ?? '',
      url: row['image_url']?.toString() ?? photoUrl,
      caption: row['caption'] as String?,
      uploadedBy: row['uploader']?.toString() == userId ? 'You' : null,
      takenAt: row['taken_at'] != null
          ? DateTime.tryParse(row['taken_at'].toString())
          : null,
      is360: is360,
      isCover: false,
    );
  }

  static const int _maxUploadBytes = 8 * 1024 * 1024;

  /// Uploads validated image bytes (works on mobile and web) and returns a
  /// public HTTPS URL.
  Future<String> uploadPhoto({
    required Uint8List bytes,
    required String userId,
  }) async {
    if (bytes.length > _maxUploadBytes) {
      throw const AppException('Photo is too large (max 8 MB).');
    }
    if (!Validators.hasAllowedImageMagicBytes(bytes)) {
      throw const AppException(
        'Unsupported image format. Please choose a JPEG, PNG, WebP, or HEIC photo.',
      );
    }
    // Declare the real content type and extension of the payload: the bucket
    // enforces an image MIME allowlist, and a PNG sent as image/jpeg would be
    // stored with a lie baked into its metadata.
    final contentType = Validators.imageContentType(bytes);
    final extension = Validators.imageExtension(bytes);
    final fileName =
        'spots/$userId/${DateTime.now().millisecondsSinceEpoch}.$extension';
    await _client.storage
        .from('photos')
        .uploadBinary(
          fileName,
          bytes,
          fileOptions: FileOptions(contentType: contentType),
        );
    final url = _client.storage.from('photos').getPublicUrl(fileName);
    if (!Validators.isSafeHttpsUrl(url)) {
      throw const AppException('Invalid storage URL returned.');
    }
    return url;
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
            is360: p['is360'] as bool? ?? false,
          ),
        )
        .where((photo) => Validators.isSafeHttpsUrl(photo.url))
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
      focalLength: row['focal_length'] as String?,
      tripodFriendly: row['tripod_friendly'] as bool?,
      accessNote: row['access_note'] as String?,
      rating: (row['rating'] as num?)?.toDouble() ?? 0,
      reviewCount: (row['review_count'] as num?)?.toInt() ?? 0,
      isHidden: (row['is_hidden'] as bool?) ?? false,
      photos: photos,
      saveCount: (row['save_count'] as num?)?.toInt() ?? 0,
      viewCount: (row['view_count'] as num?)?.toInt() ?? 0,
      likeCount: (row['like_count'] as num?)?.toInt() ?? 0,
      commentCount: (row['comment_count'] as num?)?.toInt() ?? 0,
      createdAt: row['created_at'] != null
          ? DateTime.tryParse(row['created_at'].toString())
          : null,
      submittedBy: profile?['display_name'] as String?,
      submittedById: row['submitted_by']?.toString(),
    );
  }
}

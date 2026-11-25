import 'dart:io';

import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/spot.dart';
import '../state/app_state.dart';
import 'spot_repository.dart';

/// Supabase-backed repository. Used when SUPABASE_URL and SUPABASE_ANON_KEY
/// are configured in lib/main.dart. Falls back to mock behavior otherwise.
class SupabaseSpotRepository implements SpotRepository {
  SupabaseSpotRepository();

  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<List<Spot>> fetchSpots() async {
    final response = await _client
        .from('spots')
        .select('''
          *,
          photos (*),
          profiles (display_name, avatar_url)
        ''')
        .order('save_count', ascending: false);

    return (response as List).map((row) => _spotFromRow(row)).toList();
  }

  @override
  Future<void> toggleSave(Spot spot, {required bool saved}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    if (saved) {
      await _client.from('saves').insert({
        'user_id': userId,
        'spot_id': spot.id,
      });
      await _client
          .from('spots')
          .update({'save_count': spot.saveCount + 1})
          .eq('id', spot.id);
    } else {
      await _client
          .from('saves')
          .delete()
          .eq('user_id', userId)
          .eq('spot_id', spot.id);
      await _client
          .from('spots')
          .update({'save_count': spot.saveCount - 1 < 0 ? 0 : spot.saveCount - 1})
          .eq('id', spot.id);
    }
  }

  @override
  Future<void> recordView(Spot spot) async {
    final userId = _client.auth.currentUser?.id;
    await _client.from('spot_views').insert({
      'spot_id': spot.id,
      'viewer': userId,
    });
    await _client
        .from('spots')
        .update({'view_count': spot.viewCount + 1})
        .eq('id', spot.id);
  }

  @override
  Future<Spot> submitSpot({
    required String title,
    required String description,
    required LatLng location,
    required String city,
    required List<String> tags,
    String? bestTime,
    String? photoUrl,
  }) async {
    final userId = _client.auth.currentUser?.id;
    final response = await _client.from('spots').insert({
      'title': title,
      'description': description,
      'city': city,
      'latitude': location.latitude,
      'longitude': location.longitude,
      'tags': tags,
      'best_time': bestTime,
      'submitted_by': userId,
    }).select().single();

    final spotId = response['id'] as String;

    if (photoUrl != null && photoUrl.isNotEmpty) {
      await _client.from('photos').insert({
        'spot_id': spotId,
        'uploader': userId,
        'image_url': photoUrl,
        'taken_at': DateTime.now().toIso8601String(),
      });
    }

    final created = await _client
        .from('spots')
        .select('''
          *,
          photos (*),
          profiles (display_name, avatar_url)
        ''')
        .eq('id', spotId)
        .single();

    return _spotFromRow(created);
  }

  /// Upload a photo file to Supabase Storage and return the public URL.
  Future<String> uploadPhoto(File file, String spotId) async {
    final fileName = 'spots/$spotId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _client.storage.from('photos').upload(fileName, file);
    final publicUrl = _client.storage.from('photos').getPublicUrl(fileName);
    return publicUrl;
  }

  Spot _spotFromRow(Map<String, dynamic> row) {
    final photos = (row['photos'] as List? ?? [])
        .map((p) => SpotPhoto(
              id: p['id']?.toString() ?? '',
              url: p['image_url'] ?? '',
              caption: p['caption'],
              uploadedBy: p['uploader']?.toString(),
              takenAt: p['taken_at'] != null
                  ? DateTime.tryParse(p['taken_at'])
                  : null,
            ))
        .toList();

    final profile = row['profiles'] as Map<String, dynamic>?;

    return Spot(
      id: row['id']?.toString() ?? '',
      title: row['title'] ?? '',
      location: LatLng(
        (row['latitude'] as num?)?.toDouble() ?? 0,
        (row['longitude'] as num?)?.toDouble() ?? 0,
      ),
      description: row['description'] ?? '',
      city: row['city'] ?? '',
      tags: (row['tags'] as List<dynamic>? ?? []).cast<String>(),
      bestTime: row['best_time'],
      rating: (row['rating'] as num?)?.toDouble() ?? 4.5,
      reviewCount: row['review_count'] as int? ?? 0,
      photos: photos,
      saveCount: row['save_count'] as int? ?? 0,
      viewCount: row['view_count'] as int? ?? 0,
      createdAt: row['created_at'] != null
          ? DateTime.tryParse(row['created_at'])
          : null,
      submittedBy: profile?['display_name'],
    );
  }
}

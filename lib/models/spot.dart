import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

/// A photo attached to a spot.
class SpotPhoto {
  const SpotPhoto({
    required this.id,
    required this.url,
    this.caption,
    this.uploadedBy,
    this.takenAt,
    this.bytes,
  });

  final String id;
  final String url;
  final String? caption;
  final String? uploadedBy;
  final DateTime? takenAt;

  /// Local image data for photos submitted in demo mode (no storage bucket).
  final Uint8List? bytes;
}

/// A photo-worthy location on the map.
class Spot {
  const Spot({
    required this.id,
    required this.title,
    required this.location,
    required this.photos,
    this.description = '',
    this.city = '',
    this.tags = const [],
    this.bestTime,
    this.rating = 4.5,
    this.reviewCount = 0,
    this.saveCount = 0,
    this.viewCount = 0,
    this.likeCount = 0,
    this.commentCount = 0,
    this.createdAt,
    this.submittedBy,
  });

  final String id;
  final String title;
  final LatLng location;
  final String description;
  final String city;
  final List<String> tags;

  /// Human hint like "Golden hour" / "Blue hour" / "Night".
  final String? bestTime;

  /// Community rating shown as ★ 4.9 (seed data until reviews ship).
  final double rating;
  final int reviewCount;
  final List<SpotPhoto> photos;
  final int saveCount;
  final int viewCount;
  final int likeCount;
  final int commentCount;
  final DateTime? createdAt;
  final String? submittedBy;

  /// Cover photo, with a stable placeholder for photo-less spots.
  SpotPhoto get coverPhoto => photos.isNotEmpty
      ? photos.first
      : SpotPhoto(id: '$id-cover', url: 'https://picsum.photos/seed/$id/600/600');

  String get coverUrl => coverPhoto.url;

  /// Every photo usable in the detail gallery, always non-empty.
  List<SpotPhoto> get galleryPhotos =>
      photos.isEmpty ? [coverPhoto] : photos;

  List<String> get galleryUrls =>
      galleryPhotos.map((photo) => photo.url).toList();

  /// Total engagement: every action a person can take, weighted by intent.
  ///
  /// A save is the strongest deliberate signal, a like and a comment follow,
  /// and views are capped so a viral spike cannot outrank a well-loved spot.
  /// Quality (rating) and freshness keep a brand-new spot visible.
  int get engagementCount => saveCount + likeCount + commentCount + viewCount;

  /// Algorithmic ranking score. Weights are documented on [engagementCount].
  double get score {
    final age = createdAt == null
        ? const Duration(days: 999).inDays
        : DateTime.now().difference(createdAt!).inDays;
    final freshness = age >= 30 ? 0.0 : 40.0 * (1 - age / 30);
    final viewBoost = (viewCount * 0.05).clamp(0.0, 40.0);
    final quality = rating * 6;
    return saveCount * 3 +
        likeCount * 2 +
        commentCount * 2.5 +
        viewBoost +
        quality +
        freshness;
  }

  Spot copyWith({
    String? title,
    String? description,
    LatLng? location,
    String? city,
    List<String>? tags,
    String? bestTime,
    int? saveCount,
    int? viewCount,
    int? likeCount,
    int? commentCount,
    double? rating,
    int? reviewCount,
    List<SpotPhoto>? photos,
  }) {
    return Spot(
      id: id,
      title: title ?? this.title,
      location: location ?? this.location,
      description: description ?? this.description,
      city: city ?? this.city,
      tags: tags ?? this.tags,
      bestTime: bestTime ?? this.bestTime,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      photos: photos ?? this.photos,
      saveCount: saveCount ?? this.saveCount,
      viewCount: viewCount ?? this.viewCount,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      createdAt: createdAt,
      submittedBy: submittedBy,
    );
  }
}

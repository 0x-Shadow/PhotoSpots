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
    this.is360 = false,
    this.isCover = false,
  });

  final String id;
  final String url;
  final String? caption;
  final String? uploadedBy;
  final DateTime? takenAt;

  /// Local image data for photos submitted in demo mode (no storage bucket).
  final Uint8List? bytes;

  /// True when this is an equirectangular 360° capture (DJI/Insta360/etc.).
  final bool is360;

  /// True when this photo is the spot's cover / "best" photo.
  final bool isCover;
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
    this.submittedById,
    this.focalLength,
    this.tripodFriendly,
    this.accessNote,
    this.isHidden = false,
  });

  final String id;
  final String title;
  final LatLng location;
  final String description;
  final String city;
  final List<String> tags;

  /// Human hint like "Golden hour" / "Blue hour" / "Night".
  final String? bestTime;

  /// Optional camera/access specs.
  final String? focalLength;
  final bool? tripodFriendly;
  final String? accessNote;

  /// Community rating. Only meaningful once [reviewCount] is above zero —
  /// the UI never shows it for unreviewed spots.
  final double rating;
  final int reviewCount;

  /// True when reports auto-hidden this spot from other people. The owner
  /// still receives it (RLS) and can file an appeal from the spot menu.
  final bool isHidden;
  final List<SpotPhoto> photos;
  final int saveCount;
  final int viewCount;
  final int likeCount;
  final int commentCount;
  final DateTime? createdAt;

  /// Author display name shown on cards/details.
  final String? submittedBy;

  /// Author user id (`auth.uid()` in Supabase or `'you'` in demo mode).
  final String? submittedById;

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

  /// Algorithmic ranking score evaluated at [now] so callers sorting a full
  /// list use one consistent timestamp.
  ///
  /// Combines deliberate engagement (saves, likes, comments), capped views,
  /// Bayesian-smoothed rating confidence, and 30-day freshness decay.
  double scoreAt(DateTime now) {
    final age = createdAt == null
        ? const Duration(days: 999).inDays
        : now.difference(createdAt!).inDays.clamp(0, 999);
    final freshness = age >= 30 ? 0.0 : 40.0 * (1 - age / 30);
    final viewBoost = (viewCount * 0.05).clamp(0.0, 40.0);
    // Bayesian smoothing prevents a 1-review 5.0 spot from beating a heavily
    // reviewed 4.9 landmark while still letting unreviewed new spots compete.
    const priorWeight = 10.0;
    const priorMean = 4.3;
    final bayesianRating =
        (rating * reviewCount + priorMean * priorWeight) /
        (reviewCount + priorWeight);
    final quality = bayesianRating * 6;
    return saveCount * 3 +
        likeCount * 2 +
        commentCount * 2.5 +
        viewBoost +
        quality +
        freshness;
  }

  /// Algorithmic ranking score. Weights are documented on [engagementCount].
  double get score => scoreAt(DateTime.now());

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
    String? submittedBy,
    String? submittedById,
    String? focalLength,
    bool? tripodFriendly,
    String? accessNote,
    bool? isHidden,
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
      submittedBy: submittedBy ?? this.submittedBy,
      submittedById: submittedById ?? this.submittedById,
      focalLength: focalLength ?? this.focalLength,
      tripodFriendly: tripodFriendly ?? this.tripodFriendly,
      accessNote: accessNote ?? this.accessNote,
      isHidden: isHidden ?? this.isHidden,
    );
  }

  /// Compact JSON serialization for offline Saved Spots caching.
  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'title': title,
        'lat': location.latitude,
        'lng': location.longitude,
        'description': description,
        'city': city,
        'tags': tags,
        'bestTime': bestTime,
        'rating': rating,
        'reviewCount': reviewCount,
        'saveCount': saveCount,
        'viewCount': viewCount,
        'likeCount': likeCount,
        'commentCount': commentCount,
        'createdAt': createdAt?.toIso8601String(),
        'submittedBy': submittedBy,
        'submittedById': submittedById,
        'focalLength': focalLength,
        'tripodFriendly': tripodFriendly,
        'accessNote': accessNote,
        'isHidden': isHidden,
        'photos': photos
            .map((p) => {
                  'id': p.id,
                  'url': p.url,
                  'caption': p.caption,
                  'uploadedBy': p.uploadedBy,
                  'takenAt': p.takenAt?.toIso8601String(),
                  'is360': p.is360,
                  'isCover': p.isCover,
                })
            .toList(),
      };

  static Spot fromCacheJson(Map<String, dynamic> json) {
    final rawPhotos = (json['photos'] as List?) ?? const [];
    return Spot(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      location: LatLng(
        (json['lat'] as num?)?.toDouble() ?? 0,
        (json['lng'] as num?)?.toDouble() ?? 0,
      ),
      description: json['description']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      tags: (json['tags'] as List? ?? const []).map((e) => '$e').toList(),
      bestTime: json['bestTime'] as String?,
      rating: (json['rating'] as num?)?.toDouble() ?? 4.5,
      reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
      saveCount: (json['saveCount'] as num?)?.toInt() ?? 0,
      viewCount: (json['viewCount'] as num?)?.toInt() ?? 0,
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      commentCount: (json['commentCount'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      submittedBy: json['submittedBy'] as String?,
      submittedById: json['submittedById'] as String?,
      focalLength: json['focalLength'] as String?,
      tripodFriendly: json['tripodFriendly'] as bool?,
      accessNote: json['accessNote'] as String?,
      isHidden: json['isHidden'] as bool? ?? false,
      photos: rawPhotos
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map(
            (p) => SpotPhoto(
              id: p['id']?.toString() ?? '',
              url: p['url']?.toString() ?? '',
              caption: p['caption'] as String?,
              uploadedBy: p['uploadedBy'] as String?,
              takenAt: p['takenAt'] != null
                  ? DateTime.tryParse(p['takenAt'].toString())
                  : null,
              is360: p['is360'] as bool? ?? false,
              isCover: p['isCover'] as bool? ?? false,
            ),
          )
          .toList(),
    );
  }
}

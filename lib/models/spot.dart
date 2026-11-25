import 'package:latlong2/latlong.dart';

/// A photo attached to a spot.
class SpotPhoto {
  const SpotPhoto({
    required this.id,
    required this.url,
    this.caption,
    this.uploadedBy,
    this.takenAt,
  });

  final String id;
  final String url;
  final String? caption;
  final String? uploadedBy;
  final DateTime? takenAt;
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
  /// Community rating shown as ★ 4.9 (from seed data / future reviews).
  final double rating;
  /// Review count shown next to the rating.
  final int reviewCount;
  final List<SpotPhoto> photos;
  final int saveCount;
  final int viewCount;
  final DateTime? createdAt;
  final String? submittedBy;

  /// Best photo = the spot's cover image.
  String get coverUrl => photos.isNotEmpty
      ? photos.first.url
      : 'https://picsum.photos/seed/$id/600/600';

  /// Algorithmic ranking score: saves + freshness decay + recent activity.
  ///
  /// score = saves + recency bonus + small view contribution.
  /// Freshness bonus decays from +40 to 0 over 30 days.
  double get score {
    final age = createdAt == null
        ? const Duration(days: 999).inDays
        : DateTime.now().difference(createdAt!).inDays;
    final freshness = age >= 30 ? 0.0 : 40.0 * (1 - age / 30);
    return saveCount + freshness + viewCount * 0.1;
  }

  Spot copyWith({
    int? saveCount,
    int? viewCount,
    double? rating,
    int? reviewCount,
    List<SpotPhoto>? photos,
  }) {
    return Spot(
      id: id,
      title: title,
      location: location,
      description: description,
      city: city,
      tags: tags,
      bestTime: bestTime,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      photos: photos ?? this.photos,
      saveCount: saveCount ?? this.saveCount,
      viewCount: viewCount ?? this.viewCount,
      createdAt: createdAt,
      submittedBy: submittedBy,
    );
  }
}

/// Marker clustering output: either one spot or a group at a cell.
class SpotCluster {
  const SpotCluster.spot(this.spot) : spots = null;
  const SpotCluster.group(this.spots) : spot = null;

  final Spot? spot;
  final List<Spot>? spots;

  bool get isGroup => spots != null;
}

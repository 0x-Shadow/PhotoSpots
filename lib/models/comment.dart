/// A community comment on a spot.
class SpotComment {
  const SpotComment({
    required this.id,
    required this.spotId,
    required this.authorId,
    required this.authorName,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String spotId;
  final String authorId;
  final String authorName;
  final String body;
  final DateTime createdAt;

  /// First character of the author, for the avatar bubble.
  String get initial {
    final name = authorName.trim();
    return name.isEmpty ? '?' : name[0].toUpperCase();
  }
}

import '../models/spot.dart';

/// What the app has learned about a person's taste, built only from actions
/// they took themselves (saving, liking, viewing a spot, or adding one).
///
/// Weights are deliberately explicit so the recommendation is auditable:
/// a save says more than a view, and publishing a spot says the most.
class InterestProfile {
  const InterestProfile(this.weights);

  static const saveWeight = 3;
  static const likeWeight = 2;
  static const viewWeight = 1;
  static const publishWeight = 4;

  /// Tag -> accumulated weight.
  final Map<String, int> weights;

  static const empty = InterestProfile({});

  bool get isEmpty => weights.isEmpty;

  int get totalWeight =>
      weights.values.fold(0, (sum, weight) => sum + weight);

  /// Tags strongest first, ties broken alphabetically so the UI is stable.
  List<String> topTags({int limit = 8}) {
    final entries = weights.entries.toList()
      ..sort((a, b) {
        final byWeight = b.value.compareTo(a.value);
        return byWeight != 0 ? byWeight : a.key.compareTo(b.key);
      });
    return entries.take(limit).map((entry) => entry.key).toList();
  }

  /// 0..1 affinity for a spot, based on the tags it carries.
  double affinity(Spot spot) {
    if (weights.isEmpty) return 0;
    final max = weights.values.reduce((a, b) => a > b ? a : b);
    var sum = 0;
    for (final tag in spot.tags) {
      sum += weights[tag.toLowerCase()] ?? 0;
    }
    // Batch normalization keeps one very heavy tag from flattening every other
    // signal to zero; the cap prevents tag-stuffed spots from dominating.
    return (sum / (max * 3)).clamp(0.0, 1.0);
  }

  static InterestProfile fromActivity({
    Iterable<Spot> saved = const [],
    Iterable<Spot> liked = const [],
    Iterable<Spot> viewed = const [],
    Iterable<Spot> published = const [],
  }) {
    final weights = <String, int>{};

    void add(Iterable<Spot> spots, int weight) {
      for (final spot in spots) {
        for (final tag in spot.tags) {
          final key = tag.toLowerCase();
          weights[key] = (weights[key] ?? 0) + weight;
        }
      }
    }

    add(saved, saveWeight);
    add(liked, likeWeight);
    add(viewed, viewWeight);
    add(published, publishWeight);
    return InterestProfile(weights);
  }
}

/// Ranking helpers shared by the home feed, category feeds and the map.
class SpotRanking {
  SpotRanking._();

  /// Human labels for the strongest engagement signals, used as honest
  /// reasons instead of a vague "trending" badge everywhere.
  static String fameLabel(Spot spot, List<Spot> all) {
    if (all.length > 1 && spot.id == _topBy(all, (s) => s.saveCount).id) {
      return 'Most saved';
    }
    if (all.length > 1 && spot.id == _topBy(all, (s) => s.likeCount).id) {
      return 'Most loved';
    }
    if (all.length > 1 && spot.id == _topBy(all, (s) => s.commentCount).id) {
      return 'Most discussed';
    }
    final days = spot.createdAt == null
        ? 999
        : DateTime.now().difference(spot.createdAt!).inDays;
    if (days <= 7 && spot.saveCount > 0) return 'New & rising';
    if (spot.rating >= 4.8) return 'Local favorite';
    return 'Popular';
  }

  static Spot _topBy(List<Spot> all, int Function(Spot) metric) {
    var best = all.first;
    for (final spot in all) {
      if (metric(spot) > metric(best)) best = spot;
    }
    return best;
  }

  /// Ranks spots for a person: community popularity plus personal affinity.
  ///
  /// Without a taste profile this is exactly the popularity order, so a new
  /// visitor still sees the community's real favourites.
  static List<Spot> recommend(
    List<Spot> spots,
    InterestProfile profile, {
    int? limit,
  }) {
    final ranked = List<Spot>.of(spots);
    if (profile.isEmpty) {
      ranked.sort((a, b) => b.score.compareTo(a.score));
    } else {
      final top = ranked.isEmpty ? 1.0 : ranked.first.score.abs() + 1;
      double value(Spot spot) => spot.score + profile.affinity(spot) * top;
      ranked.sort((a, b) => value(b).compareTo(value(a)));
    }
    if (limit != null && ranked.length > limit) {
      return ranked.sublist(0, limit);
    }
    return ranked;
  }
}

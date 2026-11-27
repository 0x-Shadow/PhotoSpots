import 'package:latlong2/latlong.dart';

import '../models/spot.dart';

/// What the app has learned about a person's taste, built only from actions
/// they took themselves (saving, liking, viewing a spot, or adding one).
///
/// Weights are deliberately explicit so the recommendation is auditable:
/// a save says more than a view, and publishing a spot says the most.
class InterestProfile {
  const InterestProfile(
    this.weights, {
    this.cityWeights = const {},
    this.bestTimeWeights = const {},
  });

  static const saveWeight = 3;
  static const likeWeight = 2;
  static const viewWeight = 1;
  static const publishWeight = 4;

  /// Tag -> accumulated weight.
  final Map<String, int> weights;

  /// City (lowercased) -> accumulated weight.
  final Map<String, int> cityWeights;

  /// Best time of day (lowercased) -> accumulated weight.
  final Map<String, int> bestTimeWeights;

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

  /// 0..1 affinity for a spot, combining tag overlap, city affinity, and
  /// preferred shooting time.
  double affinity(Spot spot) {
    if (weights.isEmpty && cityWeights.isEmpty && bestTimeWeights.isEmpty) {
      return 0;
    }

    var tagScore = 0.0;
    if (weights.isNotEmpty) {
      final maxTag = weights.values.reduce((a, b) => a > b ? a : b);
      var sum = 0;
      for (final tag in spot.tags) {
        sum += weights[tag.toLowerCase()] ?? 0;
      }
      // Batch normalization keeps one very heavy tag from flattening every
      // other signal to zero; the cap prevents tag-stuffed spots from winning.
      tagScore = (sum / (maxTag * 3)).clamp(0.0, 1.0);
    }

    var cityScore = 0.0;
    final cityKey = spot.city.trim().toLowerCase();
    if (cityKey.isNotEmpty && cityWeights.isNotEmpty) {
      final maxCity = cityWeights.values.reduce((a, b) => a > b ? a : b);
      cityScore = ((cityWeights[cityKey] ?? 0) / maxCity).clamp(0.0, 1.0);
    }

    var timeScore = 0.0;
    final timeKey = spot.bestTime?.trim().toLowerCase() ?? '';
    if (timeKey.isNotEmpty && bestTimeWeights.isNotEmpty) {
      final maxTime = bestTimeWeights.values.reduce((a, b) => a > b ? a : b);
      timeScore = ((bestTimeWeights[timeKey] ?? 0) / maxTime).clamp(0.0, 1.0);
    }

    return (tagScore * 0.72 + cityScore * 0.16 + timeScore * 0.12).clamp(
      0.0,
      1.0,
    );
  }

  /// Returns the strongest matching tag from this profile on [spot], if any.
  String? strongestMatchingTag(Spot spot) {
    String? bestTag;
    var bestWeight = 0;
    for (final tag in spot.tags) {
      final w = weights[tag.toLowerCase()] ?? 0;
      if (w > bestWeight) {
        bestWeight = w;
        bestTag = tag;
      }
    }
    return bestTag;
  }

  static InterestProfile fromActivity({
    Iterable<Spot> saved = const [],
    Iterable<Spot> liked = const [],
    Iterable<Spot> viewed = const [],
    Iterable<Spot> published = const [],
  }) {
    final weights = <String, int>{};
    final cityWeights = <String, int>{};
    final bestTimeWeights = <String, int>{};

    void add(Iterable<Spot> spots, int weight) {
      for (final spot in spots) {
        for (final tag in spot.tags) {
          final key = tag.toLowerCase();
          weights[key] = (weights[key] ?? 0) + weight;
        }
        final city = spot.city.trim().toLowerCase();
        if (city.isNotEmpty) {
          cityWeights[city] = (cityWeights[city] ?? 0) + weight;
        }
        final time = spot.bestTime?.trim().toLowerCase() ?? '';
        if (time.isNotEmpty) {
          bestTimeWeights[time] = (bestTimeWeights[time] ?? 0) + weight;
        }
      }
    }

    add(saved, saveWeight);
    add(liked, likeWeight);
    add(viewed, viewWeight);
    add(published, publishWeight);
    return InterestProfile(
      weights,
      cityWeights: cityWeights,
      bestTimeWeights: bestTimeWeights,
    );
  }
}

/// Ranking helpers shared by the home feed, category feeds and the map.
class SpotRanking {
  SpotRanking._();

  static const _distance = Distance();

  /// Maps the local clock hour to the matching shooting window label used on
  /// spots (`Morning light`, `Afternoon`, `Golden hour`, `Blue hour`, `Night`).
  static String lightWindowFor(DateTime now) {
    final hour = now.hour;
    if (hour >= 5 && hour < 11) return 'morning light';
    if (hour >= 11 && hour < 16) return 'afternoon';
    if (hour >= 16 && hour < 20) return 'golden hour';
    if (hour >= 20 && hour < 22) return 'blue hour';
    return 'night';
  }

  /// Contextual light match bonus (0..1) for [spot] at [now].
  static double lightMatch(Spot spot, DateTime now) {
    final best = spot.bestTime?.trim().toLowerCase() ?? '';
    if (best.isEmpty) return 0;
    final window = lightWindowFor(now);
    if (best.contains(window) || window.contains(best)) return 1.0;
    if (window == 'golden hour' && best.contains('sunset')) return 0.9;
    if (window == 'blue hour' && best.contains('night')) return 0.5;
    return 0;
  }

  /// Human labels for the strongest engagement signals, used as honest
  /// reasons instead of a vague "trending" badge everywhere.
  static String fameLabel(Spot spot, List<Spot> all, {DateTime? now}) {
    final clock = now ?? DateTime.now();
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
        : clock.difference(spot.createdAt!).inDays;
    if (days <= 7 && spot.saveCount > 0) return 'New & rising';
    if (spot.rating >= 4.8) return 'Local favorite';
    return 'Popular';
  }

  /// Honest one-line explanation of why the recommendation algorithm picked
  /// [spot] for the user right now.
  static String reasonFor(
    Spot spot, {
    required InterestProfile profile,
    required List<Spot> all,
    LatLng? userLocation,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final matchedTag = profile.strongestMatchingTag(spot);
    if (matchedTag != null) return 'Matches #$matchedTag';
    if (lightMatch(spot, clock) >= 0.9) {
      return 'Best light right now';
    }
    if (userLocation != null) {
      final km = _distance.as(LengthUnit.Kilometer, userLocation, spot.location);
      if (km <= 8) return 'Nearby pick';
    }
    return fameLabel(spot, all, now: clock);
  }

  static Spot _topBy(List<Spot> all, int Function(Spot) metric) {
    var best = all.first;
    for (final spot in all) {
      if (metric(spot) > metric(best)) best = spot;
    }
    return best;
  }

  /// Ranks spots for a person: community popularity + Bayesian quality +
  /// time-of-day light match + optional proximity decay + personal taste,
  /// followed by a light diversity pass so similar spots don't crowd the top.
  static List<Spot> recommend(
    List<Spot> spots,
    InterestProfile profile, {
    LatLng? userLocation,
    DateTime? now,
    bool diversify = true,
    int? limit,
  }) {
    if (spots.isEmpty) return const [];
    final clock = now ?? DateTime.now();

    // Base score for every spot at one frozen clock instant.
    final baseScores = <String, double>{
      for (final s in spots) s.id: s.scoreAt(clock),
    };
    final topBase = baseScores.values.fold<double>(
      1.0,
      (best, value) => value.abs() > best ? value.abs() : best,
    );

    double rankValue(Spot spot) {
      var value = baseScores[spot.id]!;
      // Time-of-day shooting light boost (up to ~12% of top score).
      value += lightMatch(spot, clock) * topBase * 0.12;
      // Smooth proximity boost when we have a real location fix.
      if (userLocation != null) {
        final km = _distance.as(LengthUnit.Kilometer, userLocation, spot.location);
        final proximity = 1.0 / (1.0 + km / 18.0);
        value += proximity * topBase * 0.18;
      }
      if (!profile.isEmpty) {
        value += profile.affinity(spot) * (topBase + 1);
      }
      return value;
    }

    final sorted = List<Spot>.of(spots)
      ..sort((a, b) => rankValue(b).compareTo(rankValue(a)));

    final result = diversify && sorted.length > 3
        ? _diversify(sorted, rankValue, topBase)
        : sorted;

    if (limit != null && result.length > limit) {
      return result.sublist(0, limit);
    }
    return result;
  }

  /// Light greedy MMR-style pass: avoids consecutive spots with identical
  /// primary tags so the top feed feels varied while keeping strong winners.
  static List<Spot> _diversify(
    List<Spot> sorted,
    double Function(Spot) scoreOf,
    double scale,
  ) {
    final remaining = List<Spot>.of(sorted);
    final out = <Spot>[remaining.removeAt(0)];
    while (remaining.isNotEmpty) {
      final prevTags = out.last.tags.map((t) => t.toLowerCase()).toSet();
      var bestIdx = 0;
      var bestAdjusted = double.negativeInfinity;
      final window = remaining.length < 6 ? remaining.length : 6;
      for (var i = 0; i < window; i++) {
        final candidate = remaining[i];
        final overlap = candidate.tags
            .where((t) => prevTags.contains(t.toLowerCase()))
            .length;
        final penalty = overlap * scale * 0.08;
        final adjusted = scoreOf(candidate) - penalty;
        if (adjusted > bestAdjusted) {
          bestAdjusted = adjusted;
          bestIdx = i;
        }
      }
      out.add(remaining.removeAt(bestIdx));
    }
    return out;
  }
}

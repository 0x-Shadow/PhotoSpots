import 'package:flutter/material.dart';

import '../models/spot.dart';
import '../theme/app_theme.dart';

/// A browsing category.
///
/// [tags] is the real contract: a spot belongs to a category when any of its
/// tags is listed here. That is why the mapping is many-to-many — a sunset
/// rooftop is both Nature and Date, and the app should say so.
class SpotCategory {
  const SpotCategory({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.tags,
    required this.seed,
  });

  final String id;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Set<String> tags;
  final String seed;
}

const spotCategories = <SpotCategory>[
  SpotCategory(
    id: 'date',
    label: 'Date',
    subtitle: 'Romantic spots',
    icon: Icons.favorite_rounded,
    color: AppColors.catDate,
    tags: {'date', 'romantic', 'couple', 'dinner', 'sunset'},
    seed: 'date-a',
  ),
  SpotCategory(
    id: 'friends',
    label: 'Friends',
    subtitle: 'Best spots together',
    icon: Icons.people_rounded,
    color: AppColors.catFriends,
    tags: {'friends', 'group', 'street', 'hangout'},
    seed: 'friends-a',
  ),
  SpotCategory(
    id: 'nature',
    label: 'Nature',
    subtitle: 'Breathtaking views',
    icon: Icons.wb_sunny_outlined,
    color: AppColors.catSunset,
    tags: {'sunset', 'skyline', 'water', 'nature', 'park', 'reflection'},
    seed: 'sunset-a',
  ),
  SpotCategory(
    id: 'culture',
    label: 'Culture',
    subtitle: 'History & art',
    icon: Icons.photo_camera_rounded,
    color: AppColors.catPhoto,
    tags: {
      'architecture',
      'landmark',
      'tiles',
      'tram',
      'iron',
      'industrial',
      'symmetry',
      'art',
      'museum',
      'hidden gem',
    },
    seed: 'photo-a',
  ),
  SpotCategory(
    id: 'relax',
    label: 'Relax',
    subtitle: 'Peaceful places',
    icon: Icons.spa_rounded,
    color: AppColors.catRelax,
    tags: {'water', 'park', 'quiet', 'cafe', 'reflection'},
    seed: 'relax-a',
  ),
  SpotCategory(
    id: 'nightlife',
    label: 'Nightlife',
    subtitle: 'After dark',
    icon: Icons.nightlife_rounded,
    color: AppColors.catNight,
    tags: {'nightlife', 'night', 'neon'},
    seed: 'night-a',
  ),
];

/// Map filter chips: label plus the category id they match (`null` = all).
const spotFilters = <({String label, String? categoryId})>[
  (label: 'All', categoryId: null),
  (label: 'Date', categoryId: 'date'),
  (label: 'Friends', categoryId: 'friends'),
  (label: 'Nature', categoryId: 'nature'),
  (label: 'Culture', categoryId: 'culture'),
  (label: 'Relax', categoryId: 'relax'),
  (label: 'Nightlife', categoryId: 'nightlife'),
];

SpotCategory? categoryById(String? id) {
  if (id == null) return null;
  for (final category in spotCategories) {
    if (category.id == id) return category;
  }
  return null;
}

/// Every category a spot genuinely belongs to, in display order.
List<SpotCategory> categoriesForSpot(Spot spot) {
  final tags = spot.tags.map((tag) => tag.toLowerCase()).toSet();
  return [
    for (final category in spotCategories)
      if (category.tags.any(tags.contains)) category,
  ];
}

/// The category used for the map pin and the "best for" label.
///
/// Picks the category with the most matching tags so a tag like `sunset`
/// (Nature, Date) resolves by the second signal rather than by array order.
SpotCategory categoryForSpot(Spot spot) {
  final tags = spot.tags.map((tag) => tag.toLowerCase()).toSet();
  SpotCategory? best;
  var bestHits = 0;
  for (final category in spotCategories) {
    final hits = category.tags.where(tags.contains).length;
    if (hits > bestHits) {
      best = category;
      bestHits = hits;
    }
  }
  return best ?? spotCategories.firstWhere((c) => c.id == 'culture');
}

/// Spots that really belong to [category].
List<Spot> spotsInCategory(Iterable<Spot> spots, SpotCategory category) {
  final tags = category.tags;
  return spots
      .where((spot) => spot.tags.any((tag) => tags.contains(tag.toLowerCase())))
      .toList();
}

/// Spots matching a category id, or all spots when [categoryId] is null.
List<Spot> spotsForFilter(Iterable<Spot> spots, String? categoryId) {
  final category = categoryById(categoryId);
  if (category == null) return List<Spot>.of(spots);
  return spotsInCategory(spots, category);
}

/// Builds the icon-and-color pin used on the map.
({IconData icon, Color color}) pinStyleForSpot(Spot spot) {
  final category = categoryForSpot(spot);
  return (icon: category.icon, color: category.color);
}

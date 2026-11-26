import 'package:flutter/material.dart';

import '../models/spot.dart';
import '../theme/app_theme.dart';

/// A browsing category: the visual tile, the tag it filters on, and the
/// icon/color used for map pins.
class SpotCategory {
  const SpotCategory({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.tag,
    required this.seed,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String tag;
  final String seed;
}

const spotCategories = <SpotCategory>[
  SpotCategory(
    label: 'Date',
    subtitle: 'Romantic spots',
    icon: Icons.favorite_rounded,
    color: AppColors.catDate,
    tag: 'date',
    seed: 'date-a',
  ),
  SpotCategory(
    label: 'Friends',
    subtitle: 'Places to hang out',
    icon: Icons.people_rounded,
    color: AppColors.catFriends,
    tag: 'friends',
    seed: 'friends-a',
  ),
  SpotCategory(
    label: 'Sunset',
    subtitle: 'Best sunset views',
    icon: Icons.wb_sunny_outlined,
    color: AppColors.catSunset,
    tag: 'sunset',
    seed: 'sunset-a',
  ),
  SpotCategory(
    label: 'Photography',
    subtitle: 'Photo hotspots',
    icon: Icons.photo_camera_rounded,
    color: AppColors.catPhoto,
    tag: 'skyline',
    seed: 'photo-a',
  ),
  SpotCategory(
    label: 'Relax',
    subtitle: 'Peaceful places',
    icon: Icons.spa_rounded,
    color: AppColors.catRelax,
    tag: 'water',
    seed: 'relax-a',
  ),
  SpotCategory(
    label: 'Nightlife',
    subtitle: 'Night views',
    icon: Icons.nightlife_rounded,
    color: AppColors.catNight,
    tag: 'nightlife',
    seed: 'night-a',
  ),
];

/// Map filter chips: label plus the tag it matches (`null` = all).
const spotFilters = <({String label, String? tag})>[
  (label: 'All', tag: null),
  (label: 'Date', tag: 'date'),
  (label: 'Friends', tag: 'friends'),
  (label: 'Sunset', tag: 'sunset'),
  (label: 'Photo', tag: 'skyline'),
];

/// Matches a spot to its best category, in display order.
SpotCategory categoryForSpot(Spot spot) {
  for (final category in spotCategories) {
    if (spot.tags.any(
      (tag) => tag.toLowerCase() == category.tag.toLowerCase(),
    )) {
      return category;
    }
  }
  return spotCategories[3];
}

/// Builds the icon-and-color pin used on the map.
({IconData icon, Color color}) pinStyleForSpot(Spot spot) {
  final category = categoryForSpot(spot);
  return (icon: category.icon, color: category.color);
}

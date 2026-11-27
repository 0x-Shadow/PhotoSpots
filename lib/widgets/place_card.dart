import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/spot.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/actions.dart';
import '../utils/categories.dart';
import '../utils/format.dart';
import '../utils/navigation.dart';
import 'spot_image.dart';

/// The golden-hour spotlight: photo, rating and trending pills, the name and
/// city, and three quick facts along the bottom.
class TrendingCard extends StatelessWidget {
  const TrendingCard({
    super.key,
    required this.spot,
    required this.heroTag,
  });

  final Spot spot;
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    final category = categoryForSpot(spot);

    return Semantics(
      button: true,
      label: 'Open ${spot.title}',
      child: GestureDetector(
        onTap: () => openSpot(context, spot, heroTag: heroTag),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0x1FFFFFFF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x80000000),
                blurRadius: 24,
                spreadRadius: -8,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(
                      tag: heroTag,
                      child: SpotImage(photo: spot.coverPhoto, iconSize: 42),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x8C000000), Color(0x00000000)],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: _Pill(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: AppColors.star,
                              size: 14,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${spot.rating.toStringAsFixed(1)} '
                              '(${formatCount(spot.reviewCount)})',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: _Pill(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.trending_up_rounded,
                              color: AppColors.trending,
                              size: 14,
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              'Trending',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.place_rounded,
                                      color: AppColors.textPrimary,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 5),
                                    Expanded(
                                      child: Text(
                                        spot.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 17,
                                          height: 1.2,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  spot.city,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            width: 42,
                            height: 42,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.arrow_forward_rounded,
                              color: AppColors.onAction,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _MetaChip(
                              icon: Icons.wb_sunny_rounded,
                              label: spot.bestTime ?? 'Any light',
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _MetaChip(
                              icon: Icons.center_focus_strong_rounded,
                              label: 'Best for ${category.label}',
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _MetaChip(
                              icon: Icons.photo_library_rounded,
                              label: '${spot.galleryPhotos.length} photos',
                            ),
                          ),
                        ],
                      ),
                    ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dark capsule that stays readable over any photograph.
class _Pill extends StatelessWidget {
  const _Pill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xA6000000),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x26FFFFFF)),
      ),
      child: child,
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 12),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact photo card for the horizontal nearby rail.
class TopPickCard extends StatelessWidget {
  const TopPickCard({
    super.key,
    required this.spot,
    required this.heroTag,
  });

  final Spot spot;
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    final saved = context.watch<AppState>().isSaved(spot.id);

    return Semantics(
      button: true,
      label: 'Open ${spot.title}',
      child: GestureDetector(
        onTap: () => openSpot(context, spot, heroTag: heroTag),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(
                      tag: heroTag,
                      child: SpotImage(photo: spot.coverPhoto),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x33000000), Color(0x00000000)],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IconButton(
                        onPressed: () => toggleSaveWithFeedback(context, spot),
                        tooltip: saved ? 'Remove from saved' : 'Save spot',
                        constraints: const BoxConstraints(
                          minWidth: AppLayout.minTapTarget,
                          minHeight: AppLayout.minTapTarget,
                        ),
                        icon: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: const BoxDecoration(
                            color: Color(0x73000000),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            saved
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_outline_rounded,
                            size: 17,
                            color: saved ? AppColors.star : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spot.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            spot.city,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.star_rounded,
                          color: AppColors.star,
                          size: 12,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          spot.rating.toStringAsFixed(1),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
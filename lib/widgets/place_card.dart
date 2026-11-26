import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/spot.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/actions.dart';
import '../utils/navigation.dart';
import 'spot_image.dart';

/// Full-width trending hero card from the reference.
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
    return Semantics(
      button: true,
      label: 'Open ${spot.title}',
      child: GestureDetector(
        onTap: () => openSpot(context, spot, heroTag: heroTag),
        child: Container(
          height: 250,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppLayout.radiusCard),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: heroTag,
                child: SpotImage(
                  photo: spot.coverPhoto,
                  iconSize: 44,
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [Color(0x66000000), Color(0x00000000)],
                  ),
                ),
              ),
              Positioned(
                top: 14,
                right: 14,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xCC161618),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.hairline),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.local_fire_department_rounded,
                          color: AppColors.trending, size: 14),
                      SizedBox(width: 5),
                      Text(
                        'Trending',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 18,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            spot.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              height: 1.2,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
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
                                    color: Color(0xD9FFFFFF),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const Text(
                                '  ·  ',
                                style: TextStyle(
                                  color: Color(0xB3FFFFFF),
                                  fontSize: 13,
                                ),
                              ),
                              const Icon(Icons.star_rounded,
                                  color: AppColors.star, size: 14),
                              const SizedBox(width: 3),
                              Text(
                                spot.rating.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_forward_rounded,
                          color: AppColors.onAction, size: 21),
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

/// Compact photo card for the horizontal "Top Picks Nearby" rail.
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
            borderRadius: BorderRadius.circular(16),
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
                    Positioned(
                      top: 6,
                      right: 6,
                      child: IconButton(
                        onPressed: () => toggleSaveWithFeedback(context, spot),
                        tooltip: saved ? 'Remove from saved' : 'Save spot',
                        constraints: const BoxConstraints(
                          minWidth: AppLayout.minTapTarget,
                          minHeight: AppLayout.minTapTarget,
                        ),
                        icon: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Color(0xB30A0A0B),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            saved
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 16,
                            color: saved ? AppColors.like : Colors.white,
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
                    const SizedBox(height: 4),
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
                        const Text(
                          ' · ',
                          style: TextStyle(
                            color: AppColors.textFaint,
                            fontSize: 12,
                          ),
                        ),
                        const Icon(Icons.star_rounded,
                            color: AppColors.star, size: 12),
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/spot.dart';
import '../screens/spot_detail_screen.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Trending hero card — full width, photo takes up most of card.
class TrendingCard extends StatelessWidget {
  const TrendingCard({super.key, required this.spot});

  final Spot spot;

  @override
  Widget build(BuildContext context) {
    final saved = context.watch<AppState>().isSaved(spot.id);

    return GestureDetector(
      onTap: () => _open(context),
      child: Container(
        height: 250,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppLayout.radiusCard),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: 'spot-photo-${spot.coverUrl}',
              child: Image.network(
                spot.coverUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: AppColors.surfaceElevated,
                  child: const Icon(Icons.landscape_rounded,
                      color: AppColors.textFaint, size: 44),
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x80000000), Color(0x00000000), Color(0xCC000000)],
                  stops: [0, 0.5, 1],
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
                  color: const Color(0xE6161618),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_fire_department_rounded,
                        color: AppColors.trending, size: 15),
                    SizedBox(width: 6),
                    Text(
                      'Trending',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Inter',
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            fontFamily: 'Inter',
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.place_rounded,
                                color: AppColors.textSecondary, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              spot.city,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                fontFamily: 'Inter',
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Icon(Icons.star_rounded,
                                color: AppColors.star, size: 15),
                            const SizedBox(width: 3),
                            Text(
                              spot.rating.toStringAsFixed(1),
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                fontFamily: 'Inter',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_forward_rounded,
                        color: AppColors.onAction, size: 22),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    final state = context.read<AppState>();
    state.recordView(spot);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SpotDetailScreen(spotId: spot.id),
      ),
    );
  }
}

/// Top Picks card — photo-forward, image dominates.
class TopPickCard extends StatelessWidget {
  const TopPickCard({super.key, required this.spot});

  final Spot spot;

  @override
  Widget build(BuildContext context) {
    final saved = context.watch<AppState>().isSaved(spot.id);

    return GestureDetector(
      onTap: () {
        context.read<AppState>().recordView(spot);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SpotDetailScreen(spotId: spot.id),
          ),
        );
      },
      child: Container(
        width: 250,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppLayout.radiusCard),
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
                    tag: 'spot-photo-${spot.coverUrl}',
                    child: Image.network(
                      spot.coverUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: AppColors.surfaceElevated,
                        child: const Icon(Icons.landscape_rounded,
                            color: AppColors.textFaint),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: GestureDetector(
                      onTap: () {
                        context.read<AppState>().toggleSave(spot);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: const BoxDecoration(
                          color: Color(0xB30A0A0B),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          size: 17,
                          color: saved ? AppColors.like : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spot.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          color: AppColors.star, size: 15),
                      const SizedBox(width: 3),
                      Text(
                        spot.rating.toStringAsFixed(1),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Inter',
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.place_rounded,
                          color: AppColors.textFaint, size: 13),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          spot.city,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textFaint,
                            fontSize: 12,
                            fontFamily: 'Inter',
                          ),
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
    );
  }
}

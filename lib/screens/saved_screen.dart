import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/spot.dart';
import '../state/app_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import '../widgets/place_card.dart';
import 'spot_detail_screen.dart';

/// Saved: rows in the reference style (photo + title + chevron) with staggered reveal.
class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final saved = state.savedSpots;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
          children: [
            const SizedBox(height: 8),
            const Text(
              'Saved',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.9,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Your favorite places.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15, fontFamily: 'Inter'),
            ),
            const SizedBox(height: 24),
            if (saved.isEmpty) ...[
              const SizedBox(height: 60),
              Center(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.accentSoft),
                      ),
                      child: const Icon(Icons.bookmark_border_rounded,
                          size: 44, color: AppColors.accent),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Nothing saved yet',
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Inter'),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tap the bookmark on any spot to save it here.',
                      style: const TextStyle(color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ] else ...[
              for (int i = 0; i < saved.length; i++) ...[
                RevealItem(
                  index: i,
                  total: saved.length,
                  child: SavedRow(spot: saved[i]),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Saved row: thumbnail + title + meta — reference's list style.
class SavedRow extends StatelessWidget {
  const SavedRow({super.key, required this.spot});

  final Spot spot;

  @override
  Widget build(BuildContext context) {
    final saved = context.watch<AppState>().isSaved(spot.id);
    return PressButton(
      child: Container(
        height: 86,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                spot.coverUrl,
                width: 74,
                height: 74,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 74,
                  height: 74,
                  color: AppColors.surface,
                  child: const Icon(Icons.landscape_rounded,
                      color: AppColors.textFaint),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    spot.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          color: AppColors.star, size: 13),
                      const SizedBox(width: 3),
                      Text(
                        spot.rating.toStringAsFixed(1),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Inter',
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.place_rounded,
                          color: AppColors.textFaint, size: 13),
                      const SizedBox(width: 3),
                      Text(
                        spot.city,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12.5, fontFamily: 'Inter'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.textFaint, size: 20),
          ],
        ),
      ),
      onTap: () {
        context.read<AppState>().recordView(spot);
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => SpotDetailScreen(spotId: spot.id)),
        );
      },
    );
  }
}

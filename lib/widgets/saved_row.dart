import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/spot.dart';
import '../screens/spot_detail_screen.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Saved row: thumbnail + title + meta — reference's list style.
class SavedRow extends StatelessWidget {
  const SavedRow({super.key, required this.spot});

  final Spot spot;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return GestureDetector(
      onTap: () {
        state.recordView(spot);
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => SpotDetailScreen(spotId: spot.id)),
        );
      },
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
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.place_rounded,
                          color: AppColors.textFaint, size: 13),
                      const SizedBox(width: 3),
                      Text(
                        spot.city,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12.5),
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
    );
  }
}

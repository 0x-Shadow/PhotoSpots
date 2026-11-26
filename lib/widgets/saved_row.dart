import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/spot.dart';
import '../state/settings_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/navigation.dart';
import 'spot_image.dart';

/// One spot row: thumbnail, title, rating, and distance or city.
///
/// Used by Saved, Categories, and Search so the list style is identical.
class SavedRow extends StatelessWidget {
  const SavedRow({
    super.key,
    required this.spot,
    this.heroTag,
    this.distanceKm,
    this.onRemove,
  });

  final Spot spot;
  final String? heroTag;
  final double? distanceKm;

  /// When provided, shows a remove button in place of the chevron.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final metric = context.watch<SettingsState>().metricUnits;

    final thumb = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SpotImage(
        photo: spot.coverPhoto,
        width: 74,
        height: 74,
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => openSpot(context, spot, heroTag: heroTag),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.hairline),
          ),
          child: SizedBox(
            height: 86,
            child: Row(
              children: [
                const SizedBox(width: 6),
                heroTag == null ? thumb : Hero(tag: heroTag!, child: thumb),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                      const SizedBox(height: 4),
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
                          if (distanceKm != null) ...[
                            const Icon(Icons.near_me_rounded,
                                color: AppColors.textFaint, size: 12),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                formatDistance(distanceKm!, metric: metric),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12.5,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            ),
                          ] else ...[
                            const Icon(Icons.place_rounded,
                                color: AppColors.textFaint, size: 13),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                spot.city,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12.5,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (onRemove != null)
                  Semantics(
                    button: true,
                    label: 'Remove ${spot.title} from saved',
                    child: IconButton(
                      onPressed: onRemove,
                      tooltip: 'Remove from saved',
                      iconSize: 20,
                      constraints: const BoxConstraints(
                        minWidth: AppLayout.minTapTarget,
                        minHeight: AppLayout.minTapTarget,
                      ),
                      icon: const Icon(Icons.bookmark_remove_outlined,
                          color: AppColors.textSecondary),
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: Icon(Icons.chevron_right_rounded,
                        color: AppColors.textFaint, size: 20),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/navigation.dart';
import '../widgets/spot_image.dart';
import '../widgets/state_views.dart';

/// Public view of a photographer's shared spots and community impact.
class AuthorProfileScreen extends StatelessWidget {
  const AuthorProfileScreen({
    super.key,
    required this.authorName,
    this.authorId,
  });

  final String authorName;
  final String? authorId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final spots = app.spotsByAuthor(
      authorId: authorId,
      authorName: authorName,
    );
    final totalSaves = spots.fold<int>(0, (sum, s) => sum + s.saveCount);
    final totalLikes = spots.fold<int>(0, (sum, s) => sum + s.likeCount);
    final initial = authorName.trim().isEmpty
        ? '?'
        : authorName.trim().substring(0, 1).toUpperCase();

    return Scaffold(
      appBar: AppBar(title: Text(authorName.isEmpty ? 'Explorer' : authorName)),
      body: SafeArea(
        child: ResponsiveBody(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [AppColors.accent, Color(0xFF7C6CFF)],
                        ),
                      ),
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            authorName.isEmpty ? 'Explorer' : authorName,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${spots.length} ${spots.length == 1 ? 'spot' : 'spots'} · '
                            '${formatCount(totalSaves)} saves · '
                            '${formatCount(totalLikes)} likes',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Shared spots',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              if (spots.isEmpty)
                const EmptyState(
                  icon: Icons.explore_outlined,
                  title: 'No spots visible',
                  message: 'Spots shared by this contributor appear here.',
                )
              else
                for (final spot in spots) ...[
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => openSpot(context, spot),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.hairline),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SpotImage(
                                photo: spot.coverPhoto,
                                width: 64,
                                height: 64,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    spot.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    spot.city.isNotEmpty
                                        ? spot.city
                                        : 'Photo spot',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: AppColors.textFaint,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

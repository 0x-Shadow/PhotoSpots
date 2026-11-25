import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/spot.dart';
import '../state/app_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';

/// Spot detail: hero photo, rating row, three fact tiles, description,
/// photo strip, and the reference's white Get Directions pill.
class SpotDetailScreen extends StatefulWidget {
  const SpotDetailScreen({super.key, required this.spotId});

  final String spotId;

  @override
  State<SpotDetailScreen> createState() => _SpotDetailScreenState();
}

class _SpotDetailScreenState extends State<SpotDetailScreen> {
  int _photoIndex = 0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final spot = state.spots.where((s) => s.id == widget.spotId).firstOrNull;
    if (spot == null) {
      return const Scaffold(body: Center(child: Text('Spot not found')));
    }
    final saved = state.isSaved(spot.id);

    return Scaffold(
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 130),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Hero(
                  spot: spot,
                  index: _photoIndex,
                  onIndexChanged: (i) => setState(() => _photoIndex = i),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        spot.title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 27,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                          fontFamily: 'Inter',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              color: AppColors.star, size: 19),
                          const SizedBox(width: 4),
                          Text(
                            spot.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Inter',
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '(${_fmt(spot.reviewCount)} reviews)',
                            style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 14, fontFamily: 'Inter'),
                            ),
                          const Spacer(),
                          const Icon(Icons.place_rounded,
                              color: AppColors.textSecondary, size: 17),
                          const SizedBox(width: 4),
                          Text(
                            '3.2 km',
                            style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 14, fontFamily: 'Inter'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 22),

                      Row(
                        children: [
                          _FactTile(
                            icon: Icons.wb_sunny_outlined,
                            title: 'Best Time',
                            value: spot.bestTime ?? 'Anytime',
                            color: AppColors.catSunset,
                          ),
                          const SizedBox(width: 10),
                          _FactTile(
                            icon: Icons.photo_camera_rounded,
                            title: 'Best Spot',
                            value: 'Top View',
                            color: AppColors.catPhoto,
                          ),
                          const SizedBox(width: 10),
                          _FactTile(
                            icon: Icons.auto_awesome_rounded,
                            title: 'Great For',
                            value: 'Photos',
                            color: AppColors.catNight,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      Text(
                        spot.description,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 15.5,
                          height: 1.6,
                          fontFamily: 'Inter',
                        ),
                      ),
                      const SizedBox(height: 24),

                      if (spot.photos.length > 1) ...[
                        SizedBox(
                          height: 120,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: spot.photos.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 10),
                            itemBuilder: (_, i) {
                              final photo = spot.photos[i];
                              final selected = i == _photoIndex;
                              return GestureDetector(
                                onTap: () => setState(() => _photoIndex = i),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  width: 160,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    border: selected
                                        ? Border.all(
                                            color: AppColors.textPrimary,
                                            width: 2)
                                        : null,
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(13),
                                    child: Image.network(
                                      photo.url,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Container(
                                        color: AppColors.surfaceElevated,
                                        child: const Icon(Icons.image,
                                            color: AppColors.textFaint),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final tag in spot.tags)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceElevated,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: AppColors.hairline),
                              ),
                              child: Text(
                                '#$tag',
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12.5,
                                    fontFamily: 'Inter'),
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

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _ActionBar(spot: spot, saved: saved),
          ),
        ],
      ),
    );
  }

  static String _fmt(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.spot,
    required this.index,
    required this.onIndexChanged,
  });

  final Spot spot;
  final int index;
  final ValueChanged<int> onIndexChanged;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SizedBox(
          height: 360,
          child: PageView.builder(
            itemCount: spot.photos.length,
            onPageChanged: onIndexChanged,
            itemBuilder: (_, i) => Hero(
              tag: 'spot-photo-${spot.photos[i].url}',
              child: Image.network(
                spot.photos[i].url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: AppColors.surfaceElevated,
                  child: const Icon(Icons.landscape_rounded,
                      color: AppColors.textFaint, size: 48),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 120,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.55),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                PressButton(
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0x1AFFFFFF),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: const Icon(Icons.arrow_back_rounded,
                        color: AppColors.textPrimary, size: 22),
                  ),
                  onTap: () => Navigator.of(context).pop(),
                ),
                const Spacer(),
                PressButton(
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0x1AFFFFFF),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: const Icon(Icons.ios_share_rounded,
                        color: AppColors.textPrimary, size: 22),
                  ),
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Share link copied (demo)')),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (spot.photos.length > 1)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${index + 1} / ${spot.photos.length}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Inter'),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FactTile extends StatelessWidget {
  const _FactTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.spot, required this.saved});

  final Spot spot;
  final bool saved;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: AppColors.hairline),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            PressButton(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Icon(
                  saved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                  color: saved ? AppColors.star : AppColors.textPrimary,
                  size: 24,
                ),
              ),
              onTap: () {
                context.read<AppState>().toggleSave(spot);
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(
                          saved ? 'Removed from Saved' : 'Saved to your list'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
              },
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 56,
                child: PressButton(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.action,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    alignment: Alignment.center,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.navigation_rounded, size: 20),
                        SizedBox(width: 10),
                        Text('Get Directions',
                            style: TextStyle(fontFamily: 'Inter')),
                      ],
                    ),
                  ),
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Opening directions… (demo)')),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

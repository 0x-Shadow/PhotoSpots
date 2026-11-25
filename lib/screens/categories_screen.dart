import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/spot.dart';
import '../state/app_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import '../widgets/saved_row.dart';
import 'spot_detail_screen.dart';

/// Categories grid — the reference's photo-card grid with labels.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({
    super.key,
    this.filterTag,
    this.allOnly = false,
  });

  final String? filterTag;
  final bool allOnly;

  static const _categories = [
    ('Sunset', 'Best sunset views', Icons.wb_sunny_outlined, 'sunset', AppColors.catSunset, 'sunset-a'),
    ('Photography', 'Photo hotspots', Icons.photo_camera_rounded, 'skyline', AppColors.catPhoto, 'photo-a'),
    ('Street', 'Urban exploring', Icons.directions_walk_rounded, 'street', AppColors.catDate, 'street-a'),
    ('Architecture', 'Lines & light', Icons.apartment_rounded, 'architecture', AppColors.catFriends, 'arch-a'),
    ('Relax', 'Peaceful places', Icons.spa_rounded, 'water', AppColors.catRelax, 'relax-a'),
    ('Nightlife', 'After dark', Icons.nightlife_rounded, 'nightlife', AppColors.catNight, 'night-a'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
          children: [
            const SizedBox(height: 8),
            const Text(
              'Categories',
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
              'Find the perfect vibe.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15, fontFamily: 'Inter'),
            ),
            const SizedBox(height: 22),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 0.82,
              ),
              itemCount: _categories.length,
              itemBuilder: (_, i) {
                return RevealItem(
                  index: i,
                  total: _categories.length,
                  child: _CategoryCard(cat: _categories[i]),
                );
              },
            ),
            if (filterTag != null || allOnly) ...[
              const SizedBox(height: 28),
              Text(
                allOnly ? 'All spots' : '#$filterTag',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 12),
              _SpotList(tag: filterTag),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.cat});

  final (String, String, IconData, String, Color, String) cat;

  @override
  Widget build(BuildContext context) {
    final (name, subtitle, icon, _, color, seed) = cat;
    return PressButton(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              'https://picsum.photos/seed/$seed/500/700',
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(color: AppColors.surfaceElevated),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x33000000), Color(0xE6000000)],
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xB3161618),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xCCFFFFFF),
                      fontSize: 12.5,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CategoriesScreen(filterTag: cat.$4),
          ),
        );
      },
    );
  }
}

class _SpotList extends StatelessWidget {
  const _SpotList({this.tag});

  final String? tag;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final spots = tag == null
        ? state.spots
        : state.spots
            .where((s) => s.tags.any((t) => t.toLowerCase() == tag!.toLowerCase()))
            .toList();
    return Column(
      children: [
        for (int i = 0; i < spots.length; i++) ...[
          RevealItem(
            index: i,
            total: spots.length,
            child: SavedRow(spot: spots[i]),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

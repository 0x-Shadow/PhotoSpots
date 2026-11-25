import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/spot.dart';
import '../state/app_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import '../widgets/place_card.dart';
import 'categories_screen.dart';
import 'spot_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final spots = state.rankedSpots;
    final trending = spots.isNotEmpty ? spots.first : null;
    final topPicks = spots.take(8).toList();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 130),
          children: [
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _greeting(),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Inter',
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Explore the\nbest places.',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 34,
                          height: 1.06,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.2,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                ),
                PressButton(
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0x1AFFFFFF),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: const Icon(Icons.search_rounded,
                        color: AppColors.textPrimary, size: 22),
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const CategoriesScreen(allOnly: true)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),

            if (trending != null) ...[
              RevealItem(
                index: 0,
                total: 10,
                child: TrendingCard(spot: trending),
              ),
              const SizedBox(height: 28),
            ],

            _SectionHeader(
              title: 'Categories',
              action: 'See all',
              onAction: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CategoriesScreen()),
              ),
            ),
            const SizedBox(height: 14),
            const Padding(
              padding: EdgeInsets.only(right: 20),
              child: CategoryTiles(),
            ),
            const SizedBox(height: 28),

            _SectionHeader(
              title: 'Top Picks Nearby',
              action: 'See all',
              onAction: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CategoriesScreen()),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: topPicks.length,
                itemBuilder: (_, i) {
                  return RevealItem(
                    index: i + 1,
                    total: topPicks.length + 1,
                    child: SizedBox(
                      width: 250,
                      child: TopPickCard(spot: topPicks[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning,';
    if (h < 18) return 'Good afternoon,';
    return 'Good evening,';
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.action,
    required this.onAction,
  });

  final String title;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                fontFamily: 'Inter',
              ),
            ),
          ),
          GestureDetector(
            onTap: onAction,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'See all',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Inter',
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: AppColors.textSecondary, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CategoryTiles extends StatelessWidget {
  const CategoryTiles({super.key});

  static const _tiles = [
    _Cat('Date', Icons.favorite_rounded, AppColors.catDate),
    _Cat('Friends', Icons.people_rounded, AppColors.catFriends),
    _Cat('Sunset', Icons.wb_sunny_outlined, AppColors.catSunset),
    _Cat('Photo', Icons.photo_camera_rounded, AppColors.catPhoto),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _tiles.length,
        itemBuilder: (_, i) {
          return RevealItem(
            index: i,
            total: _tiles.length,
            child: SizedBox(
              width: 60,
              child: _CategoryTile(tile: _tiles[i]),
            ),
          );
        },
      ),
    );
  }
}

class _Cat {
  const _Cat(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.tile});

  final _Cat tile;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Center(
        child: Icon(tile.icon, color: tile.color, size: 24),
      ),
    );
  }
}

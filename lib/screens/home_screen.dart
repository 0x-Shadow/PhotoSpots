import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import '../utils/categories.dart';
import '../utils/format.dart';
import '../widgets/place_card.dart';
import '../widgets/state_views.dart';
import 'categories_screen.dart';
import 'map_screen.dart';
import 'search_screen.dart';
import 'submit_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final ranked = state.rankedSpots;
    final trending = ranked.isNotEmpty ? ranked.first : null;
    final goldenHourSpots = ranked.where(
      (spot) => spot.bestTime?.toLowerCase().contains('golden') ?? false,
    );
    final goldenHourSpot = goldenHourSpots.isEmpty
        ? trending
        : goldenHourSpots.first;

    final nearby = state.nearby(state.referenceLocation);
    final picks = (nearby.isNotEmpty ? nearby : ranked).take(8).toList();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ResponsiveBody(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 130),
            children: [
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _greeting(),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Inter',
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Find a place\nworth going out for.',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 33,
                            height: 1.05,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.2,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  PressButton(
                    semanticLabel: 'Search photo spots',
                    onTap: () =>
                        Navigator.of(context)
                            .push(AppMotion.slideUp(const SearchScreen())),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0x14FFFFFF),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: const Icon(
                        Icons.search_rounded,
                        color: AppColors.textPrimary,
                        size: 21,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              const _CommunityPromise(),
              const SizedBox(height: 26),

              if (trending == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  child: EmptyState(
                    icon: Icons.explore_rounded,
                    title: 'No spots yet',
                    message: 'Add the first photo spot and start the map for everyone.',
                    actionLabel: 'Add a spot',
                    onAction: () =>
                        Navigator.of(context)
                            .push(AppMotion.slideUpModal(const SubmitScreen())),
                  ),
                )
              else ...[
                _SectionHeader(
                  title: 'Tonight’s golden hour',
                  actionLabel: 'See map',
                  onAction: () =>
                      Navigator.of(context)
                          .push(AppMotion.slideUp(const MapScreen())),
                ),
                const SizedBox(height: 8),
                Text(
                  goldenHourSpot == null
                      ? 'Places shared by people who know the view.'
                      : 'Best light near ${goldenHourSpot.city} — saved by the community.',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.35,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 14),
                RevealItem(
                  index: 0,
                  total: 8,
                  child: TrendingCard(
                    spot: trending,
                    heroTag: 'trending-${trending.id}',
                  ),
                ),
                const SizedBox(height: 26),

                _SectionHeader(
                  title: 'Categories',
                  onAction: () =>
                      Navigator.of(context)
                          .push(AppMotion.slideUp(const CategoriesScreen())),
                ),
                const SizedBox(height: 14),
                _CategoryRow(
                  onTap: (tag) => Navigator.of(
                    context,
                  ).push(AppMotion.slideUp(CategoriesScreen(filterTag: tag))),
                ),
                const SizedBox(height: 26),

                _SectionHeader(
                  title: state.hasUserLocation
                      ? 'Good near you'
                      : 'Community favorites',
                  onAction: () => Navigator.of(context).push(
                    AppMotion.slideUp(const CategoriesScreen(allOnly: true)),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 196,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    itemCount: picks.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, i) {
                      return RevealItem(
                        index: i + 1,
                        total: picks.length + 1,
                        child: SizedBox(
                          width: 236,
                          child: TopPickCard(
                            spot: picks[i],
                            heroTag: 'pick-$i-${picks[i].id}',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning.';
    if (hour < 18) return 'Good afternoon.';
    return 'Good evening.';
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.onAction,
    this.actionLabel = 'See all',
  });

  final String title;
  final VoidCallback onAction;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              fontFamily: 'Inter',
            ),
          ),
        ),
        Semantics(
          button: true,
          label: '$actionLabel $title',
          child: PressButton(
            onTap: onAction,
            child: Container(
              constraints: const BoxConstraints(minHeight: 40),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionLabel,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Inter',
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: AppColors.textSecondary,
                    size: 15,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.onTap});

  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final categories = spotCategories.take(4).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 4 : 2;
        final tileWidth =
            (constraints.maxWidth - ((columns - 1) * 10)) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < categories.length; i++)
              SizedBox(
                width: tileWidth,
                child: RevealItem(
                  index: i,
                  total: categories.length,
                  child: _CategoryTile(
                    category: categories[i],
                    onTap: () => onTap(categories[i].tag),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CommunityPromise extends StatelessWidget {
  const _CommunityPromise();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.people_alt_rounded,
                color: AppColors.accent,
                size: 18,
              ),
            ),
          ),
          SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Places people actually recommend',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Inter',
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Save the view. Share the secret, thoughtfully.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onTap});

  final SpotCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${category.label} spots',
      child: PressButton(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Container(
                height: 58,
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Center(
                  child: Icon(category.icon, color: category.color, size: 23),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                category.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

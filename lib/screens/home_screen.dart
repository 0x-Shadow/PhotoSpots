import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/spot.dart';
import '../state/app_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import '../utils/categories.dart';
import '../widgets/place_card.dart';
import '../widgets/state_views.dart';
import 'categories_screen.dart';
import 'root_shell.dart';
import 'search_screen.dart';
import 'spot_list_screen.dart';
import 'submit_screen.dart';

/// Photo-led home: a hero image with the greeting, a glass recommendation
/// banner, a swipeable golden-hour spotlight, and topic cards.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final ranked = state.recommendedSpots;
    final spotlight = ranked.isNotEmpty ? ranked.first : null;

    final golden = ranked.where(
      (spot) => spot.bestTime?.toLowerCase().contains('golden') ?? false,
    );
    final goldenHour = golden.isNotEmpty ? golden.first : spotlight;

    final nearby = state.nearby(state.referenceLocation);
    final picks = (nearby.isNotEmpty ? nearby : ranked)
        .where((spot) => spot.id != spotlight?.id)
        .take(8)
        .toList();

    final spotlightPool = [
      ?goldenHour,
      ...ranked.where((spot) => spot.id != goldenHour?.id),
    ].take(4).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _HeroHeader(greeting: _greeting()),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 130),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CommunityBanner(
                  onTap: () => Navigator.of(context).push(
                    AppMotion.slideUp(
                      SpotListScreen(
                        title: 'Recommended by people',
                        subtitle:
                            'The spots the community actually saves, likes and talks about.',
                        spotIds: [
                          for (final spot in state.recommendedSpots) spot.id,
                        ],
                      ),
                    ),
                  ),
                ),
                if (spotlight == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 56),
                    child: EmptyState(
                      icon: Icons.explore_rounded,
                      title: 'No spots yet',
                      message: 'Add the first photo spot and start the map.',
                      actionLabel: 'Add a spot',
                      onAction: () => Navigator.of(context).push(
                        AppMotion.slideUpModal(const SubmitScreen()),
                      ),
                    ),
                  )
                else ...[
                  const SizedBox(height: 28),
                  _SectionHeader(
                    icon: Icons.wb_sunny_rounded,
                    iconColor: AppColors.star,
                    title: 'Tonight’s golden hour',
                    actionLabel: 'See map',
                    onAction: () => RootShell.openTab(1),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Best light near ${goldenHour?.city ?? spotlight.city} — '
                    'saved by the community.',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SpotlightCarousel(spots: spotlightPool),
                  const SizedBox(height: 30),
                  _SectionHeader(
                    icon: Icons.layers_rounded,
                    iconColor: AppColors.textSecondary,
                    title: 'Categories',
                    actionLabel: 'See all',
                    onAction: () => Navigator.of(context).push(
                      AppMotion.slideUp(const CategoriesScreen()),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _CategoriesGrid(
                    onTap: (category) => Navigator.of(context).push(
                      AppMotion.slideUp(
                        SpotListScreen(
                          title: category.label,
                          subtitle: category.subtitle,
                          spotIds: [
                            for (final spot
                                in state.categorySpots(category))
                              spot.id,
                          ],
                          emptyMessage:
                              'No ${category.label.toLowerCase()} spots yet. Add the first one.',
                        ),
                      ),
                    ),
                  ),
                  if (picks.isNotEmpty) ...[
                    const SizedBox(height: 30),
                    _SectionHeader(
                      icon: Icons.near_me_rounded,
                      iconColor: AppColors.accent,
                      title: state.hasUserLocation
                          ? 'Near you'
                          : 'Community favorites',
                      actionLabel: 'See all',
                      onAction: () => Navigator.of(context).push(
                        AppMotion.slideUp(
                          SpotListScreen(
                            title: state.hasUserLocation
                                ? 'Near you'
                                : 'Community favorites',
                            subtitle: state.hasUserLocation
                                ? 'Closest photo spots to your current location.'
                                : 'The most saved and liked spots right now.',
                            spotIds: [for (final spot in picks) spot.id],
                            sort: state.hasUserLocation
                                ? SpotListSort.nearest
                                : SpotListSort.popular,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 208,
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
                              width: 230,
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 18) return 'Good afternoon,';
    return 'Good evening,';
  }
}

/// The photo hero: greeting, headline, search, fading into the page ground.
class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.greeting});

  final String greeting;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return SizedBox(
      height: topInset + 196,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/home_hero.jpg',
            fit: BoxFit.cover,
            alignment: Alignment.centerRight,
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: AppColors.surface),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xCC0A0A0B),
                  Color(0x660A0A0B),
                  Color(0xD90A0A0B),
                ],
                stops: [0.0, 0.5, 0.9],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x000A0A0B),
                  Color(0x000A0A0B),
                  AppColors.background,
                ],
                stops: [0.0, 0.62, 1.0],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            top: topInset + 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.place_rounded,
                      color: AppColors.textSecondary,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        greeting,
                        style: const TextStyle(
                          color: Color(0xFFC7C7CC),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    PressButton(
                      semanticLabel: 'Search photo spots',
                      onTap: () => Navigator.of(context).push(
                        AppMotion.slideUp(const SearchScreen()),
                      ),
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: const Color(0x26FFFFFF),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0x33FFFFFF)),
                        ),
                        child: const Icon(
                          Icons.search_rounded,
                          color: AppColors.textPrimary,
                          size: 23,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Find a place\nworth going out for.',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 37,
                    height: 1.04,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.8,
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

/// A swipeable spotlight. The dots are a real page indicator, not decoration.
class _SpotlightCarousel extends StatefulWidget {
  const _SpotlightCarousel({required this.spots});

  final List<Spot> spots;

  @override
  State<_SpotlightCarousel> createState() => _SpotlightCarouselState();
}

class _SpotlightCarouselState extends State<_SpotlightCarousel> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.spots.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: 352,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.spots.length,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder: (_, i) => Padding(
              padding: EdgeInsets.only(
                right: i == widget.spots.length - 1 ? 0 : 12,
              ),
              child: TrendingCard(
                spot: widget.spots[i],
                heroTag: 'trending-${widget.spots[i].id}',
              ),
            ),
          ),
        ),
        if (widget.spots.length > 1) ...[
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.spots.length; i++)
                AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : AppMotion.quick,
                  curve: AppMotion.easeOut,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page
                        ? AppColors.textPrimary
                        : const Color(0x40FFFFFF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _CommunityBanner extends StatelessWidget {
  const _CommunityBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressButton(
      semanticLabel: 'Places people actually recommend',
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xE61E1E23), Color(0xE60F0F11)],
          ),
          border: Border.all(color: const Color(0x24FFFFFF)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.14),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.28),
                ),
              ),
              child: const Icon(
                Icons.groups_rounded,
                color: AppColors.accent,
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Places people actually recommend',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Real spots. Real experiences.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.onAction,
    required this.actionLabel,
    this.icon,
    this.iconColor = AppColors.textSecondary,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;
  final IconData? icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
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
              padding: const EdgeInsets.only(left: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionLabel,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 3),
                  const Icon(
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

/// Two columns of wide category cards with a faint photo behind each.
class _CategoriesGrid extends StatelessWidget {
  const _CategoriesGrid({required this.onTap});

  final ValueChanged<SpotCategory> onTap;

  @override
  Widget build(BuildContext context) {
    final categories = spotCategories.take(4).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 4 : 2;
        final spacing = 10.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (var i = 0; i < categories.length; i++)
              SizedBox(
                width: width,
                child: RevealItem(
                  index: i,
                  total: categories.length,
                  child: SizedBox(
                    height: 84,
                    child: _CategoryCard(
                      category: categories[i],
                      onTap: () => onTap(categories[i]),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.onTap});

  final SpotCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${category.label} — ${category.subtitle}',
      child: PressButton(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                'https://picsum.photos/seed/${category.seed}/400/220',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const ColoredBox(color: AppColors.surfaceElevated),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0xF20A0A0B), Color(0xB30A0A0B)],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 10, 6, 10),
                child: Row(
                  children: [
                    Icon(category.icon, color: category.color, size: 21),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            category.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            category.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textSecondary,
                      size: 18,
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
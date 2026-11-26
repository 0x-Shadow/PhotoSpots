import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/spot.dart';
import '../state/app_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import '../utils/categories.dart';
import '../utils/format.dart';
import '../widgets/saved_row.dart';
import '../widgets/state_views.dart';
import 'search_screen.dart';

/// Category grid plus an optional filtered list of spots.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({
    super.key,
    this.filterTag,
    this.allOnly = false,
  });

  final String? filterTag;
  final bool allOnly;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ResponsiveBody(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
            children: [
              Row(
                children: [
                  PressButton(
                    semanticLabel: 'Back',
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0x14FFFFFF),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: const Icon(Icons.arrow_back_rounded,
                          color: AppColors.textPrimary, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Categories',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.9,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Find the perfect vibe.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PressButton(
                    semanticLabel: 'Search photo spots',
                    onTap: () => Navigator.of(context)
                        .push(AppMotion.slideUp(const SearchScreen())),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0x14FFFFFF),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: const Icon(Icons.search_rounded,
                          color: AppColors.textPrimary, size: 21),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 700 ? 3 : 2;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.78,
                    ),
                    itemCount: spotCategories.length,
                    itemBuilder: (_, i) {
                      final category = spotCategories[i];
                      return RevealItem(
                        index: i,
                        total: spotCategories.length,
                        child: _CategoryCard(
                          category: category,
                          onTap: () => Navigator.of(context).push(
                            AppMotion.slideUp(
                              CategoriesScreen(filterTag: category.tag),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
              if (filterTag != null || allOnly) ...[
                const SizedBox(height: 26),
                _SpotList(tag: filterTag, allOnly: allOnly),
              ],
            ],
          ),
        ),
      ),
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
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(
                  width: double.infinity,
                  child: Image.network(
                    'https://picsum.photos/seed/${category.seed}/500/500',
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        Container(color: AppColors.surface),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 12),
                child: Row(
                  children: [
                    Icon(category.icon, color: category.color, size: 17),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            category.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
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

class _SpotList extends StatelessWidget {
  const _SpotList({this.tag, required this.allOnly});

  final String? tag;
  final bool allOnly;

  List<Spot> _filter(AppState state) {
    if (allOnly || tag == null) return state.rankedSpots;
    return state.spots
        .where((spot) =>
            spot.tags.any((t) => t.toLowerCase() == tag!.toLowerCase()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final spots = _filter(state);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          allOnly ? 'All spots' : '#${tag!}',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 12),
        if (spots.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: EmptyState(
              icon: Icons.photo_camera_outlined,
              title: 'Nothing here yet',
              message: 'No spots match this category yet. Add the first one.',
            ),
          )
        else
          for (var i = 0; i < spots.length; i++) ...[
            RevealItem(
              index: i,
              total: spots.length,
              child: SavedRow(
                spot: spots[i],
                heroTag: 'category-${tag ?? 'all'}-${spots[i].id}',
                distanceKm: state.hasUserLocation
                    ? state.distanceKm(state.referenceLocation, spots[i])
                    : null,
              ),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

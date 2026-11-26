import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/spot.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import '../utils/actions.dart';
import '../utils/categories.dart';
import '../utils/format.dart';
import '../utils/share.dart';
import '../widgets/spot_image.dart';
import '../widgets/spot_mini_map.dart';
import '../widgets/state_views.dart';
import 'categories_screen.dart';

/// Spot detail: hero, honest facts, a location preview and one reachable
/// action bar. All type comes from the theme; sections are divided by space
/// and hairlines rather than nested cards.
class SpotDetailScreen extends StatefulWidget {
  const SpotDetailScreen({super.key, required this.spotId, this.heroTag});

  final String spotId;
  final String? heroTag;

  @override
  State<SpotDetailScreen> createState() => _SpotDetailScreenState();
}

class _SpotDetailScreenState extends State<SpotDetailScreen> {
  final _pageController = PageController();
  int _photoIndex = 0;
  bool _scrolled = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final settings = context.watch<SettingsState>();
    final spot = state.spotById(widget.spotId);

    if (spot == null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'Spot not found',
                  message: 'It may have been removed from the map.',
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Go back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final saved = state.isSaved(spot.id);
    final hasFix = state.hasReferenceFix;
    final photos = spot.galleryPhotos;
    if (_photoIndex >= photos.length) _photoIndex = 0;

    return Scaffold(
      body: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.depth != 0 ||
                  notification.metrics.axis != Axis.vertical) {
                return false;
              }
              final scrolled = notification.metrics.pixels > 180;
              if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
              return false;
            },
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 130),
              child: ResponsiveBody(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HeroGallery(
                      spot: spot,
                      photos: photos,
                      controller: _pageController,
                      index: _photoIndex,
                      heroTag: widget.heroTag,
                      onPageChanged: (i) => setState(() => _photoIndex = i),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(spot.title, style: Theme.of(context).textTheme.displaySmall?.copyWith(fontSize: 27, letterSpacing: -0.9)),
                          const SizedBox(height: 9),
                          _RatingRow(
                            spot: spot,
                            hasFix: hasFix,
                            distanceLabel: hasFix
                                ? formatDistance(
                                    state.distanceKm(
                                      state.referenceLocation,
                                      spot,
                                    ),
                                    metric: settings.metricUnits,
                                  )
                                : 'demo area',
                          ),
                          const SizedBox(height: 18),
                          SpotMiniMap(
                            point: spot.location,
                            label: 'Open ${spot.title} on the map',
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              _FactTile(
                                icon: Icons.wb_sunny_outlined,
                                title: 'Best time',
                                value: spot.bestTime ?? 'Anytime',
                                color: AppColors.catSunset,
                              ),
                              const SizedBox(width: 9),
                              _FactTile(
                                icon: Icons.category_rounded,
                                title: 'Category',
                                value: categoryForSpot(spot).label,
                                color: AppColors.catPhoto,
                              ),
                              const SizedBox(width: 9),
                              _FactTile(
                                icon: Icons.bookmark_outline_rounded,
                                title: 'Saves',
                                value: formatCount(spot.saveCount),
                                color: AppColors.accent,
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Text(
                            spot.description,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          if (spot.city.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(Icons.place_rounded,
                                    color: AppColors.textFaint, size: 15),
                                const SizedBox(width: 4),
                                Text(
                                  spot.city,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ],
                          if (spot.tags.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final tag in spot.tags)
                                  InkWell(
                                    onTap: () => Navigator.of(context).push(
                                      AppMotion.slideUp(
                                        CategoriesScreen(filterTag: tag),
                                      ),
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                    child: Container(
                                      constraints:
                                          const BoxConstraints(minHeight: 34),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceElevated,
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(
                                            color: AppColors.hairline),
                                      ),
                                      child: Text(
                                        '#$tag',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          if (photos.length > 1) ...[
                            const SizedBox(height: 22),
                            SizedBox(
                              height: 110,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: photos.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 10),
                                itemBuilder: (_, i) {
                                  final selected = i == _photoIndex;
                                  return GestureDetector(
                                    onTap: () {
                                      setState(() => _photoIndex = i);
                                      _pageController.animateToPage(
                                        i,
                                        duration: AppMotion.quick,
                                        curve: AppMotion.easeOut,
                                      );
                                    },
                                    child: AnimatedContainer(
                                      duration: AppMotion.quick,
                                      width: 150,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: selected
                                              ? AppColors.textPrimary
                                              : Colors.transparent,
                                          width: 2,
                                        ),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: SpotImage(photo: photos[i]),
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
                  ],
                ),
              ),
            ),
          ),
          _StickyBar(scrolled: _scrolled, spot: spot),
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
}

/// Back and Share stay reachable after the hero leaves the viewport.
class _StickyBar extends StatelessWidget {
  const _StickyBar({required this.scrolled, required this.spot});

  final bool scrolled;
  final Spot spot;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        key: const ValueKey('sticky_bar'),
        opacity: scrolled ? 1 : 0,
        duration: AppMotion.instant,
        child: IgnorePointer(
          ignoring: !scrolled,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.background.withValues(alpha: 0.92),
              border: const Border(bottom: BorderSide(color: AppColors.hairline)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    PressButton(
                      semanticLabel: 'Back',
                      onTap: () => Navigator.of(context).maybePop(),
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(Icons.arrow_back_rounded,
                            color: AppColors.textPrimary, size: 22),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      spot.title,
                      style: Theme.of(context).textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    PressButton(
                      semanticLabel: 'Share this spot',
                      onTap: () => shareLocationLink(
                        context,
                        lat: spot.location.latitude,
                        lng: spot.location.longitude,
                        title: spot.title,
                      ),
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(Icons.ios_share_rounded,
                            color: AppColors.textPrimary, size: 21),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RatingRow extends StatelessWidget {
  const _RatingRow({
    required this.spot,
    required this.hasFix,
    required this.distanceLabel,
  });

  final Spot spot;
  final bool hasFix;
  final String distanceLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Row(
      children: [
        const Icon(Icons.star_rounded, color: AppColors.star, size: 18),
        const SizedBox(width: 4),
        Text(
          spot.rating.toStringAsFixed(1),
          style: theme.titleSmall?.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            '(${formatCount(spot.reviewCount)} reviews)',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.bodySmall,
          ),
        ),
        const Spacer(),
        Icon(Icons.near_me_rounded,
            color: hasFix ? AppColors.textSecondary : AppColors.textFaint,
            size: 15),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            hasFix ? distanceLabel : 'Near the demo city',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _HeroGallery extends StatelessWidget {
  const _HeroGallery({
    required this.spot,
    required this.photos,
    required this.controller,
    required this.index,
    required this.heroTag,
    required this.onPageChanged,
  });

  final Spot spot;
  final List<SpotPhoto> photos;
  final PageController controller;
  final int index;
  final String? heroTag;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
      child: SizedBox(
        height: 380,
        child: Stack(
          children: [
            PageView.builder(
              controller: controller,
              itemCount: photos.length,
              onPageChanged: onPageChanged,
              itemBuilder: (_, i) {
                final image = SpotImage(photo: photos[i], iconSize: 48);
                if (i == 0 && heroTag != null) {
                  return Hero(tag: heroTag!, child: image);
                }
                return image;
              },
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 130,
              child: IgnorePointer(
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
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    PressButton(
                      semanticLabel: 'Back',
                      onTap: () => Navigator.of(context).maybePop(),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.hairline),
                        ),
                        child: const Icon(Icons.arrow_back_rounded,
                            color: AppColors.textPrimary, size: 21),
                      ),
                    ),
                    const Spacer(),
                    PressButton(
                      semanticLabel: 'Share this spot',
                      onTap: () => shareLocationLink(
                        context,
                        lat: spot.location.latitude,
                        lng: spot.location.longitude,
                        title: spot.title,
                      ),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.hairline),
                        ),
                        child: const Icon(Icons.ios_share_rounded,
                            color: AppColors.textPrimary, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (photos.length > 1)
              Positioned(
                bottom: 14,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${index + 1} / ${photos.length}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Colors.white,
                          ),
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
    final theme = Theme.of(context).textTheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(height: 9),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.bodySmall,
            ),
            const SizedBox(height: 2),
            Text(
              value,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.titleSmall,
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
    final theme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: ResponsiveBody(
          child: Row(
            children: [
              Semantics(
                button: true,
                label: saved ? 'Remove from saved' : 'Save spot',
                child: PressButton(
                  onTap: () => toggleSaveWithFeedback(context, spot),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: Icon(
                      saved
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_outline_rounded,
                      color: saved ? AppColors.star : AppColors.textPrimary,
                      size: 23,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Semantics(
                button: true,
                label: 'Share this spot',
                child: PressButton(
                  onTap: () => shareLocationLink(
                    context,
                    lat: spot.location.latitude,
                    lng: spot.location.longitude,
                    title: spot.title,
                  ),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: const Icon(Icons.ios_share_rounded,
                        color: AppColors.textPrimary, size: 22),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: PressButton(
                  semanticLabel: 'Get directions to ${spot.title}',
                  onTap: () => openDirections(context, spot),
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.action,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.navigation_rounded,
                            color: AppColors.onAction, size: 18),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Get Directions',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.labelLarge?.copyWith(
                              color: AppColors.onAction,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

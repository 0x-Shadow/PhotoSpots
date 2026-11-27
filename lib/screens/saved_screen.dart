import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/spot.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import '../utils/actions.dart';
import '../utils/format.dart';
import '../utils/navigation.dart';
import '../widgets/spot_image.dart';
import '../widgets/state_views.dart';
import 'spot_list_screen.dart';

enum _SavedSort { recent, alphabetical, nearest }

/// The saved collection: a two-column photo grid, a distance-aware sort, and a
/// clear way to remove places you no longer want.
class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  _SavedSort _sort = _SavedSort.recent;

  List<Spot> _sorted(List<Spot> saved, AppState state) {
    final list = [...saved];
    switch (_sort) {
      case _SavedSort.recent:
        break;
      case _SavedSort.alphabetical:
        list.sort((a, b) => a.title.toLowerCase().compareTo(
              b.title.toLowerCase(),
            ));
      case _SavedSort.nearest:
        final origin = state.referenceLocation;
        list.sort(
          (a, b) => state
              .distanceKm(origin, a)
              .compareTo(state.distanceKm(origin, b)),
        );
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final saved = _sorted(state.savedSpots, state);
    final cities = saved
        .map((spot) => spot.city.trim())
        .where((city) => city.isNotEmpty)
        .toSet()
        .length;

    return Scaffold(
      body: SafeArea(
        child: ResponsiveBody(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 130),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'YOUR COLLECTION',
                          style: TextStyle(
                            color: AppColors.textFaint,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.6,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Saved',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 34,
                            height: 1.05,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (saved.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0x14FFFFFF),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppColors.hairline),
                        ),
                        child: Text(
                          cities > 1
                              ? '${saved.length} · $cities cities'
                              : '${saved.length} ${saved.length == 1 ? 'place' : 'places'}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              if (saved.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: EmptyState(
                    icon: Icons.bookmark_border_rounded,
                    title: 'Nothing saved yet',
                    message:
                        'Tap the bookmark on any spot and it lands here, ready '
                        'for your next photo walk.',
                    actionLabel: 'Find spots',
                    onAction: () => Navigator.of(context).push(
                      AppMotion.slideUp(
                        SpotListScreen(
                          title: 'Find spots',
                          subtitle:
                              'The community favourites, ranked by saves, likes and comments.',
                          spotIds: [
                            for (final spot in state.recommendedSpots)
                              spot.id,
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              else ...[
                _SortBar(
                  sort: _sort,
                  onChanged: (value) => setState(() => _sort = value),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 620 ? 3 : 2;
                    final spacing = 12.0;
                    final width =
                        (constraints.maxWidth - spacing * (columns - 1)) /
                            columns;
                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [
                        for (var i = 0; i < saved.length; i++)
                          SizedBox(
                            width: width,
                            child: RevealItem(
                              index: i,
                              total: saved.length,
                              child: SizedBox(
                                height: width * 1.36,
                                child: SavedSpotCard(
                                  spot: saved[i],
                                  heroTag: 'saved-${saved[i].id}',
                                  distanceKm: state.hasReferenceFix
                                      ? state.distanceKm(
                                          state.referenceLocation,
                                          saved[i],
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SortBar extends StatelessWidget {
  const _SortBar({required this.sort, required this.onChanged});

  final _SavedSort sort;
  final ValueChanged<_SavedSort> onChanged;

  static const _items = <({_SavedSort value, String label, IconData icon})>[
    (value: _SavedSort.recent, label: 'Recent', icon: Icons.schedule_rounded),
    (value: _SavedSort.alphabetical, label: 'A–Z', icon: Icons.sort_by_alpha_rounded),
    (value: _SavedSort.nearest, label: 'Nearest', icon: Icons.near_me_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: PressButton(
              semanticLabel: 'Sort saved by ${_items[i].label}',
              onTap: () => onChanged(_items[i].value),
              child: AnimatedContainer(
                duration: AppMotion.instant,
                height: 42,
                decoration: BoxDecoration(
                  color: sort == _items[i].value
                      ? AppColors.action
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: sort == _items[i].value
                        ? AppColors.action
                        : AppColors.hairline,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _items[i].icon,
                      size: 15,
                      color: sort == _items[i].value
                          ? AppColors.onAction
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _items[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: sort == _items[i].value
                              ? AppColors.onAction
                              : AppColors.textSecondary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A photo-forward saved card. The bookmark removes the spot and the card
/// opens the detail page with a shared Hero.
class SavedSpotCard extends StatelessWidget {
  const SavedSpotCard({
    super.key,
    required this.spot,
    required this.heroTag,
    this.distanceKm,
  });

  final Spot spot;
  final String heroTag;
  final double? distanceKm;

  @override
  Widget build(BuildContext context) {
    final units = context.watch<SettingsState>().metricUnits;

    return Semantics(
      button: true,
      label: 'Open ${spot.title}',
      child: GestureDetector(
        onTap: () => openSpot(context, spot, heroTag: heroTag),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(
                      tag: heroTag,
                      child: SpotImage(photo: spot.coverPhoto),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x59000000), Color(0x00000000)],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Semantics(
                        button: true,
                        label: 'Remove ${spot.title} from saved',
                        child: IconButton(
                          onPressed: () =>
                              toggleSaveWithFeedback(context, spot),
                          tooltip: 'Remove from saved',
                          constraints: const BoxConstraints(
                            minWidth: AppLayout.minTapTarget,
                            minHeight: AppLayout.minTapTarget,
                          ),
                          icon: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: const BoxDecoration(
                              color: Color(0x80000000),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.bookmark_rounded,
                              color: AppColors.star,
                              size: 17,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (spot.bestTime != null)
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xA6000000),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            spot.bestTime!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 9, 11, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spot.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          color: AppColors.star,
                          size: 12,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          spot.rating.toStringAsFixed(1),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            distanceKm != null
                                ? formatDistance(distanceKm!, metric: units)
                                : spot.city,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textFaint,
                              fontSize: 11.5,
                            ),
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
      ),
    );
  }
}

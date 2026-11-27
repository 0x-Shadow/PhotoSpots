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
import '../utils/ranking.dart';
import '../widgets/spot_image.dart';
import '../widgets/state_views.dart';

enum SpotListSort { popular, newest, nearest }

/// A real feed of spots — used by category tiles, the recommendation banner and
/// every "See all" link. It always shows spots, never a chooser, and explains
/// why the order looks the way it does.
class SpotListScreen extends StatefulWidget {
  const SpotListScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.spotIds,
    this.emptyMessage = 'No spots in this collection yet.',
    this.sort = SpotListSort.popular,
    this.showRanking = true,
  });

  final String title;
  final String subtitle;
  final List<String> spotIds;
  final String emptyMessage;
  final SpotListSort sort;
  final bool showRanking;

  @override
  State<SpotListScreen> createState() => _SpotListScreenState();
}

class _SpotListScreenState extends State<SpotListScreen> {
  late SpotListSort _sort = widget.sort;

  List<Spot> _resolve(AppState state) {
    final byId = {for (final spot in state.spots) spot.id: spot};
    final spots = [
      for (final id in widget.spotIds)
        if (byId[id] != null) byId[id]!,
    ];

    switch (_sort) {
      case SpotListSort.popular:
        final profile = state.interestProfile;
        return SpotRanking.recommend(spots, profile);
      case SpotListSort.newest:
        spots.sort((a, b) {
          final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });
      case SpotListSort.nearest:
        final origin = state.referenceLocation;
        spots.sort(
          (a, b) => state
              .distanceKm(origin, a)
              .compareTo(state.distanceKm(origin, b)),
        );
    }
    return spots;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final spots = _resolve(state);
    final personalized = state.hasTasteProfile;

    return Scaffold(
      body: SafeArea(
        child: ResponsiveBody(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PressButton(
                    semanticLabel: 'Back',
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(
                      width: 44,
                      height: 44,
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: const Color(0x14FFFFFF),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: const Icon(
                        Icons.arrow_back_rounded,
                        color: AppColors.textPrimary,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 27,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.9,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.subtitle,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${spots.length} ${spots.length == 1 ? 'spot' : 'spots'}',
                      style: const TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (personalized && _sort == SpotListSort.popular)
                    Row(
                      children: [
                        const Icon(
                          Icons.auto_awesome_rounded,
                          color: AppColors.accent,
                          size: 13,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Tuned to your saves',
                          style: TextStyle(
                            color: AppColors.accent.withValues(alpha: 0.9),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _SortBar(
                sort: _sort,
                onChanged: (value) => setState(() => _sort = value),
              ),
              const SizedBox(height: 18),
              if (spots.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: EmptyState(
                    icon: Icons.photo_camera_outlined,
                    title: 'Nothing here yet',
                    message: widget.emptyMessage,
                  ),
                )
              else
                for (var i = 0; i < spots.length; i++) ...[
                  RevealItem(
                    index: i,
                    total: spots.length,
                    child: _RankRow(
                      spot: spots[i],
                      rank: i + 1,
                      showRank: widget.showRanking,
                      fameLabel: SpotRanking.fameLabel(spots[i], spots),
                      distanceKm: state.hasReferenceFix
                          ? state.distanceKm(state.referenceLocation, spots[i])
                          : null,
                      heroTag: 'list-${widget.title}-${spots[i].id}',
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

class _SortBar extends StatelessWidget {
  const _SortBar({required this.sort, required this.onChanged});

  final SpotListSort sort;
  final ValueChanged<SpotListSort> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = {
      SpotListSort.popular: 'Popular',
      SpotListSort.newest: 'Newest',
      SpotListSort.nearest: 'Nearest',
    };

    return Row(
      children: [
        for (final value in SpotListSort.values) ...[
          PressButton(
            onTap: () => onChanged(value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: value == sort ? AppColors.action : const Color(0x14FFFFFF),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: value == sort ? AppColors.action : AppColors.hairline,
                ),
              ),
              child: Text(
                labels[value]!,
                style: TextStyle(
                  color: value == sort
                      ? AppColors.onAction
                      : AppColors.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.spot,
    required this.rank,
    required this.showRank,
    required this.fameLabel,
    required this.distanceKm,
    required this.heroTag,
  });

  final Spot spot;
  final int rank;
  final bool showRank;
  final String fameLabel;
  final double? distanceKm;
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final metric = context.watch<SettingsState>().metricUnits;
    final saved = state.isSaved(spot.id);
    final liked = state.isLiked(spot.id);

    return Semantics(
      button: true,
      label: 'Open ${spot.title}',
      child: GestureDetector(
        onTap: () => openSpot(context, spot, heroTag: heroTag),
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showRank)
                SizedBox(
                  width: 22,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '$rank',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Hero(
                  tag: heroTag,
                  child: SpotImage(photo: spot.coverPhoto, width: 78, height: 92),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        spot.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14.5,
                          height: 1.22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accentSoft,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              fameLabel,
                              style: const TextStyle(
                                color: AppColors.accent,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              distanceKm != null
                                  ? formatDistance(distanceKm!, metric: metric)
                                  : spot.city,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textFaint,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 9,
                        runSpacing: 3,
                        children: [
                          _Metric(
                            icon: Icons.bookmark_rounded,
                            value: formatCount(spot.saveCount),
                            color: AppColors.star,
                          ),
                          _Metric(
                            icon: Icons.favorite_rounded,
                            value: formatCount(spot.likeCount),
                            color: AppColors.like,
                          ),
                          _Metric(
                            icon: Icons.forum_rounded,
                            value: formatCount(spot.commentCount),
                            color: AppColors.accent,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Column(
                children: [
                  IconButton(
                    onPressed: () => toggleSaveWithFeedback(context, spot),
                    tooltip: saved ? 'Remove from saved' : 'Save spot',
                    constraints: const BoxConstraints(
                      minWidth: AppLayout.minTapTarget,
                      minHeight: AppLayout.minTapTarget,
                    ),
                    icon: Icon(
                      saved
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_outline_rounded,
                      color: saved ? AppColors.star : AppColors.textSecondary,
                      size: 20,
                    ),
                  ),
                  IconButton(
                    onPressed: () => toggleLikeWithFeedback(context, spot),
                    tooltip: liked ? 'Unlike' : 'Like',
                    constraints: const BoxConstraints(
                      minWidth: AppLayout.minTapTarget,
                      minHeight: AppLayout.minTapTarget,
                    ),
                    icon: Icon(
                      liked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: liked ? AppColors.like : AppColors.textSecondary,
                      size: 19,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

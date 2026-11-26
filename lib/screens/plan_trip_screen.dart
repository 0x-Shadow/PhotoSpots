import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import '../utils/categories.dart';
import '../utils/format.dart';
import '../widgets/saved_row.dart';
import '../widgets/spot_image.dart';
import '../widgets/state_views.dart';
import 'submit_screen.dart';

/// "Plan Your Trip" — turns saved spots into a simple, filterable itinerary.
class PlanTripScreen extends StatefulWidget {
  const PlanTripScreen({super.key});

  @override
  State<PlanTripScreen> createState() => _PlanTripScreenState();
}

class _PlanTripScreenState extends State<PlanTripScreen> {
  String? _tag;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final saved = state.savedSpots;
    final itinerary = _tag == null
        ? saved
        : saved
            .where((spot) =>
                spot.tags.any((t) => t.toLowerCase() == _tag!.toLowerCase()))
            .toList();

    final city = saved.isNotEmpty ? saved.first.city : 'your city';
    final days = saved.isEmpty ? 0 : (saved.length / 5).ceil();
    final hero = saved.isNotEmpty
        ? saved.first
        : (state.rankedSpots.isNotEmpty ? state.rankedSpots.first : null);

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
                          'Plan Your Trip',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Create the perfect experience.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PressButton(
                    semanticLabel: 'Add a spot to your trip',
                    onTap: () => Navigator.of(context)
                        .push(AppMotion.slideUpModal(const SubmitScreen())),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0x14FFFFFF),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: const Icon(Icons.add_rounded,
                          color: AppColors.textPrimary, size: 23),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (hero != null)
                Semantics(
                  button: true,
                  label: 'Open trip preview',
                  child: GestureDetector(
                    onTap: saved.isEmpty
                        ? null
                        : () => Navigator.of(context).push(
                              AppMotion.slideUp(
                                const _ItineraryScreen(),
                              ),
                            ),
                    child: Container(
                      height: 180,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        color: AppColors.surface,
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          SpotImage(photo: hero.coverPhoto),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0x1A000000), Color(0xD9000000)],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 16,
                            right: 16,
                            bottom: 14,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        saved.isEmpty
                                            ? 'Start a trip'
                                            : '$city Weekend',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        saved.isEmpty
                                            ? 'Save spots to build an itinerary'
                                            : '${saved.length} '
                                                '${saved.length == 1 ? 'place' : 'places'} · '
                                                '$days ${days == 1 ? 'day' : 'days'}',
                                        style: const TextStyle(
                                          color: Color(0xD9FFFFFF),
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                      Icons.arrow_forward_rounded,
                                      color: AppColors.onAction,
                                      size: 20),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 22),
              const Text(
                'Quick Filters',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  itemCount: spotCategories.take(5).length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final category = spotCategories[i];
                    final active = category.tag == _tag;
                    return GestureDetector(
                      onTap: () => setState(
                        () => _tag = active ? null : category.tag,
                      ),
                      child: AnimatedContainer(
                        duration: AppMotion.instant,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: active
                              ? AppColors.action
                              : AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: active
                                ? AppColors.action
                                : AppColors.hairline,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              category.icon,
                              size: 14,
                              color: active
                                  ? AppColors.onAction
                                  : category.color,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              category.label,
                              style: TextStyle(
                                color: active
                                    ? AppColors.onAction
                                    : AppColors.textSecondary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Your itinerary',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 12),
              if (saved.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: EmptyState(
                    icon: Icons.route_rounded,
                    title: 'No stops yet',
                    message:
                        'Save a few spots and they will become your itinerary.',
                  ),
                )
              else if (itinerary.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: EmptyState(
                    icon: Icons.filter_alt_off_rounded,
                    title: 'No stops for this filter',
                    message: 'Clear the filter to see the whole trip.',
                  ),
                )
              else
                for (var i = 0; i < itinerary.length; i++) ...[
                  RevealItem(
                    index: i,
                    total: itinerary.length,
                    child: SavedRow(
                      spot: itinerary[i],
                      heroTag: 'trip-${itinerary[i].id}',
                      distanceKm: state.hasUserLocation
                          ? state.distanceKm(
                              state.referenceLocation, itinerary[i])
                          : null,
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

/// Tapping the preview opens the full itinerary list.
class _ItineraryScreen extends StatelessWidget {
  const _ItineraryScreen();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final saved = state.savedSpots;

    return Scaffold(
      appBar: AppBar(title: const Text('Your itinerary')),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        itemCount: saved.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => SavedRow(
          spot: saved[i],
          heroTag: 'trip-sheet-${saved[i].id}',
        ),
      ),
    );
  }
}

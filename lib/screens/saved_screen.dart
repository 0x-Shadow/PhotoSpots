import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/spot.dart';
import '../state/app_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import '../utils/actions.dart';
import '../utils/format.dart';
import '../widgets/saved_row.dart';
import '../widgets/state_views.dart';

/// Saved spots in the reference list style, with sorting and swipe removal.
class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  bool _sortAlphabetically = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final saved = [...state.savedSpots];
    if (_sortAlphabetically) {
      saved.sort((a, b) => a.title.compareTo(b.title));
    }

    return Scaffold(
      body: SafeArea(
        child: ResponsiveBody(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
            children: [
              const SizedBox(height: 6),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Saved',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.9,
                      ),
                    ),
                  ),
                  PressButton(
                    semanticLabel: _sortAlphabetically
                        ? 'Sort by recently saved'
                        : 'Sort alphabetically',
                    onTap: () => setState(
                      () => _sortAlphabetically = !_sortAlphabetically,
                    ),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0x14FFFFFF),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: Icon(
                        _sortAlphabetically
                            ? Icons.schedule_rounded
                            : Icons.sort_by_alpha_rounded,
                        color: AppColors.textPrimary,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              const Text(
                'Your favorite places.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 22),
              if (saved.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: EmptyState(
                    icon: Icons.bookmark_border_rounded,
                    title: 'Nothing saved yet',
                    message:
                        'Tap the bookmark on any spot and it will show up here.',
                  ),
                )
              else
                for (var i = 0; i < saved.length; i++) ...[
                  RevealItem(
                    index: i,
                    total: saved.length,
                    child: _RemovableRow(spot: saved[i]),
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

class _RemovableRow extends StatelessWidget {
  const _RemovableRow({required this.spot});

  final Spot spot;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Dismissible(
      key: ValueKey('saved-${spot.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.bookmark_remove_rounded,
            color: AppColors.danger, size: 22),
      ),
      onDismissed: (_) => toggleSaveWithFeedback(context, spot),
      child: SavedRow(
        spot: spot,
        heroTag: 'saved-${spot.id}',
        distanceKm: state.hasUserLocation
            ? state.distanceKm(state.referenceLocation, spot)
            : null,
      ),
    );
  }
}

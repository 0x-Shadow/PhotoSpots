import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/spot.dart';
import '../state/app_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/saved_row.dart';
import '../widgets/state_views.dart';

/// Live search across spot names, cities, tags, and best-time hints.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<Spot> _results(AppState state) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return const [];

    final matches = state.spots.where((spot) {
      return spot.title.toLowerCase().contains(query) ||
          spot.city.toLowerCase().contains(query) ||
          spot.description.toLowerCase().contains(query) ||
          (spot.bestTime?.toLowerCase().contains(query) ?? false) ||
          spot.tags.any((tag) => tag.toLowerCase().contains(query));
    }).toList();

    if (state.hasUserLocation) {
      matches.sort((a, b) => state
          .distanceKm(state.referenceLocation, a)
          .compareTo(state.distanceKm(state.referenceLocation, b)));
    }
    return matches;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final results = _results(state);
    final hasQuery = _query.trim().isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: ResponsiveBody(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: Row(
                  children: [
                    PressButton(
                      semanticLabel: 'Back',
                      onTap: () => Navigator.of(context).maybePop(),
                      child: Container(
                        width: AppLayout.minTapTarget,
                        height: AppLayout.minTapTarget,
                        decoration: BoxDecoration(
                          color: const Color(0x1AFFFFFF),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.hairline),
                        ),
                        child: const Icon(Icons.arrow_back_rounded,
                            color: AppColors.textPrimary, size: 22),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontFamily: 'Inter',
                          fontSize: 15,
                        ),
                        onChanged: (value) => setState(() => _query = value),
                        decoration: InputDecoration(
                          hintText: 'Places, cities, tags…',
                          prefixIcon: const Icon(Icons.search_rounded,
                              color: AppColors.textFaint, size: 20),
                          suffixIcon: hasQuery
                              ? IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () {
                                    _controller.clear();
                                    setState(() => _query = '');
                                    _focusNode.requestFocus();
                                  },
                                  icon: const Icon(Icons.close_rounded,
                                      color: AppColors.textFaint, size: 19),
                                )
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: !hasQuery
                    ? _Suggestions(
                        tags: _popularTags(state),
                        onPick: (tag) {
                          _controller.text = tag;
                          _controller.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: tag.length,
                          );
                          setState(() => _query = tag);
                        },
                      )
                    : results.isEmpty
                        ? const Center(
                            child: EmptyState(
                              icon: Icons.search_off_rounded,
                              title: 'No matches',
                              message:
                                  'Try a different place, city, or tag.',
                            ),
                          )
                        : ListView.separated(
                            padding:
                                const EdgeInsets.fromLTRB(16, 8, 16, 120),
                            itemCount: results.length + 1,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              if (i == 0) {
                                return Padding(
                                  padding: const EdgeInsets.only(
                                      bottom: 2, top: 2),
                                  child: Text(
                                    '${results.length} '
                                    '${results.length == 1 ? 'spot' : 'spots'}',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12.5,
                                      fontFamily: 'Inter',
                                    ),
                                  ),
                                );
                              }
                              final spot = results[i - 1];
                              return SavedRow(
                                spot: spot,
                                heroTag: 'search-${spot.id}',
                                distanceKm: state.hasUserLocation
                                    ? state.distanceKm(
                                        state.referenceLocation, spot)
                                    : null,
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _popularTags(AppState state) {
    final counts = <String, int>{};
    for (final spot in state.spots) {
      for (final tag in spot.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final tags = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return tags.take(8).toList();
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.tags, required this.onPick});

  final List<String> tags;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        const Text(
          'Browse by tag',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            fontFamily: 'Inter',
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Tap a tag to see every spot that fits.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in tags)
              InkWell(
                onTap: () => onPick(tag),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  constraints:
                      const BoxConstraints(minHeight: 40, minWidth: 44),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.hairline),
                  ),
                  child: Text(
                    '#$tag',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

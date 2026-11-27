import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../models/spot.dart';
import '../state/app_state.dart';
import '../state/auth_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import '../utils/categories.dart';
import '../utils/format.dart';
import '../utils/navigation.dart';
import '../widgets/location_prompt.dart';
import '../widgets/spot_image.dart';
import 'auth_screen.dart';
import 'plan_trip_screen.dart';
import 'settings_screen.dart';

/// Profile: a real account surface, the numbers the app actually tracks, and
/// the taste profile behind the recommendations.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final auth = context.watch<AuthState>();
    final saved = state.savedSpots;
    final submitted = state.submittedSpots;

    return Scaffold(
      body: SafeArea(
        child: ResponsiveBody(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 130),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'PROFILE',
                      style: TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ),
                  PressButton(
                    semanticLabel: 'Open settings',
                    onTap: () => Navigator.of(context)
                        .push(AppMotion.slideUp(const SettingsScreen())),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0x14FFFFFF),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: const Icon(
                        Icons.settings_rounded,
                        color: AppColors.textPrimary,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _IdentityCard(auth: auth, onEdit: () => _editProfile(context)),
              const SizedBox(height: 12),
              _AccountActions(auth: auth),
              const SizedBox(height: 16),
              _StatsRow(
                saved: saved.length,
                liked: state.likedCount,
                viewed: state.viewedCount,
                submitted: submitted.length,
              ),
              const SizedBox(height: 26),
              _Interests(state: state),
              const SizedBox(height: 26),
              _SavesPreview(saved: saved),
              if (submitted.isNotEmpty) ...[
                const SizedBox(height: 26),
                _YourSpots(spots: submitted),
              ],
              const SizedBox(height: 26),
              _Shortcuts(state: state),
              const SizedBox(height: 26),
              Center(
                child: Text(
                  '${AppInfo.name} v${AppInfo.version}',
                  style: const TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editProfile(BuildContext context) async {
    final auth = context.read<AuthState>();
    final messenger = ScaffoldMessenger.of(context);
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditProfileSheet(auth: auth),
    );
    if (result == true) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Profile updated.')),
      );
    }
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.auth, required this.onEdit});

  final AuthState auth;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1D1D22), Color(0xFF111113)],
        ),
        border: Border.all(color: AppColors.hairline),
        boxShadow: const [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 24,
            spreadRadius: -8,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -50,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.accent.withValues(alpha: 0.22),
                    AppColors.accent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    padding: const EdgeInsets.all(2.5),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.accent, Color(0xFF7C6CFF)],
                      ),
                    ),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF16161A),
                      ),
                      child: Text(
                        auth.initials,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          auth.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          auth.isSignedIn
                              ? auth.email
                              : auth.isLocalOnlyMode
                                  ? 'Demo profile on this device'
                                  : 'Browsing as a guest',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PressButton(
                    semanticLabel: 'Edit profile',
                    onTap: onEdit,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0x1FFFFFFF),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: const Icon(
                        Icons.edit_rounded,
                        color: AppColors.textPrimary,
                        size: 17,
                      ),
                    ),
                  ),
                ],
              ),
              if (auth.bio.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  auth.bio,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Chip(
                    icon: auth.isSignedIn
                        ? Icons.verified_user_rounded
                        : Icons.person_outline_rounded,
                    label: auth.statusLabel,
                    color: auth.isSignedIn
                        ? AppColors.success
                        : AppColors.accent,
                  ),
                  if (auth.city.isNotEmpty)
                    _Chip(
                      icon: Icons.place_rounded,
                      label: auth.city,
                      color: AppColors.textSecondary,
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sign-in / sign-out entry points. One primary action, never a dead end.
class _AccountActions extends StatelessWidget {
  const _AccountActions({required this.auth});

  final AuthState auth;

  @override
  Widget build(BuildContext context) {
    if (auth.isSignedIn) {
      return Row(
        children: [
          Expanded(
            child: _AccountButton(
              icon: Icons.sync_rounded,
              label: 'Saves sync across devices',
              tone: AppColors.success,
              onTap: null,
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () async {
              await auth.signOut();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Signed out.')),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.hairline),
              minimumSize: const Size(96, 48),
            ),
            child: const Text('Sign out'),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: PressButton(
            semanticLabel: 'Create an account',
            onTap: () => Navigator.of(context).push(
              AppMotion.slideUp(const AuthScreen(startInSignUp: true)),
            ),
            child: Container(
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.action,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Create account',
                style: TextStyle(
                  color: AppColors.onAction,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).push(
              AppMotion.slideUp(const AuthScreen()),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.hairline),
              minimumSize: const Size.fromHeight(50),
            ),
            child: const Text('Sign in'),
          ),
        ),
      ],
    );
  }
}

class _AccountButton extends StatelessWidget {
  const _AccountButton({
    required this.icon,
    required this.label,
    required this.tone,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 50),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(icon, color: tone, size: 16),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11.5,
                height: 1.3,
              ),
            ),
          ),
          if (onTap != null) const Icon(Icons.chevron_right_rounded, size: 16),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.saved,
    required this.liked,
    required this.viewed,
    required this.submitted,
  });

  final int saved;
  final int liked;
  final int viewed;
  final int submitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _Stat(value: '$saved', label: 'Saved'),
            const VerticalDivider(width: 1, color: AppColors.hairline),
            _Stat(value: '$liked', label: 'Likes'),
            const VerticalDivider(width: 1, color: AppColors.hairline),
            _Stat(value: '$viewed', label: 'Viewed'),
            const VerticalDivider(width: 1, color: AppColors.hairline),
            _Stat(value: '$submitted', label: 'Shared'),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows what the recommendation engine has learned, and lets the person
/// forget the implicit part (views).
class _Interests extends StatelessWidget {
  const _Interests({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final categories = state.affinityCategories;
    final tags = state.topInterests;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Your interests',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            if (state.viewedCount > 0)
              TextButton(
                onPressed: () async {
                  await state.clearViewHistory();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('View history cleared.')),
                  );
                },
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Clear views'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          categories.isEmpty
              ? 'Save, like or open a few spots and recommendations start '
                  'adapting to you.'
              : 'Built from your saves, likes and views. ${_summary(categories)}',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12.5,
            height: 1.45,
          ),
        ),
        if (categories.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in categories.take(4))
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: category.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: category.color.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(category.icon, color: category.color, size: 13),
                      const SizedBox(width: 5),
                      Text(
                        category.label,
                        style: TextStyle(
                          color: category.color,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Top tags: ${tags.take(5).map((tag) => '#$tag').join('  ')}',
              style: const TextStyle(
                color: AppColors.textFaint,
                fontSize: 11.5,
                height: 1.5,
              ),
            ),
          ],
        ],
      ],
    );
  }

  static String _summary(List<SpotCategory> categories) {
    final names = categories.take(2).map((c) => c.label.toLowerCase()).join(' and ');
    return 'You lean $names.';
  }
}

class _SavesPreview extends StatelessWidget {
  const _SavesPreview({required this.saved});

  final List<Spot> saved;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Your saves',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            Text(
              saved.isEmpty ? 'Nothing yet' : '${saved.length} saved',
              style: const TextStyle(
                color: AppColors.textFaint,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (saved.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.hairline),
            ),
            child: const Text(
              'Bookmark a spot and it will appear here for quick access.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          )
        else
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: saved.length.clamp(0, 8),
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final spot = saved[i];
                return Semantics(
                  button: true,
                  label: 'Open ${spot.title}',
                  child: GestureDetector(
                    onTap: () => openSpot(
                      context,
                      spot,
                      heroTag: 'profile-save-${spot.id}',
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 92,
                        height: 92,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Hero(
                              tag: 'profile-save-${spot.id}',
                              child: SpotImage(photo: spot.coverPhoto),
                            ),
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Color(0x00000000), Color(0xCC000000)],
                                ),
                              ),
                            ),
                            Positioned(
                              left: 8,
                              right: 8,
                              bottom: 7,
                              child: Text(
                                spot.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _YourSpots extends StatelessWidget {
  const _YourSpots({required this.spots});

  final List<Spot> spots;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your spots',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 10),
        for (final spot in spots) ...[
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => openSpot(context, spot),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SpotImage(
                        photo: spot.coverPhoto,
                        width: 48,
                        height: 48,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
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
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${formatCount(spot.saveCount)} saves · '
                            '${formatCount(spot.likeCount)} likes',
                            style: const TextStyle(
                              color: AppColors.textFaint,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textFaint,
                      size: 18,
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

class _Shortcuts extends StatelessWidget {
  const _Shortcuts({required this.state});

  final AppState state;

  String get _locationLabel {
    if (state.hasUserLocation) return 'Live location on';
    if (state.hasCachedFix) return 'Using your last location';
    return 'Location not set';
  }

  IconData get _locationIcon {
    if (state.hasUserLocation) return Icons.my_location_rounded;
    if (state.hasCachedFix) return Icons.location_on_rounded;
    return Icons.location_off_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final reference = state.referenceLocation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              Icon(
                _locationIcon,
                color: state.hasReferenceFix
                    ? AppColors.accent
                    : AppColors.textFaint,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _locationLabel,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${reference.latitude.toStringAsFixed(4)}, '
                      '${reference.longitude.toStringAsFixed(4)}',
                      style: const TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => runLocationFlow(context, appState: state),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(state.hasUserLocation ? 'Refresh' : 'Enable'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Column(
            children: [
              _ShortcutRow(
                icon: Icons.map_outlined,
                title: 'Plan a trip',
                onTap: () => Navigator.of(context)
                    .push(AppMotion.slideUp(const PlanTripScreen())),
              ),
              const Divider(height: 1, color: AppColors.hairline),
              _ShortcutRow(
                icon: Icons.tune_rounded,
                title: 'Settings',
                onTap: () => Navigator.of(context)
                    .push(AppMotion.slideUp(const SettingsScreen())),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0x14FFFFFF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.textSecondary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textFaint,
                size: 19,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Edits the local profile and mirrors it to the signed-in row.
class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({required this.auth});

  final AuthState auth;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final _name = TextEditingController(text: widget.auth.displayName);
  late final _bio = TextEditingController(text: widget.auth.bio);
  late final _city = TextEditingController(text: widget.auth.city);
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final result = await widget.auth.updateProfile(
      name: _name.text,
      bio: _bio.text,
      city: _city.text,
    );
    if (!mounted) return;
    if (!result.success) {
      setState(() => _error = result.message);
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Edit profile',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('profile_name'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Display name'),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('profile_bio'),
              controller: _bio,
              maxLines: 2,
              maxLength: 140,
              decoration: const InputDecoration(
                labelText: 'Bio',
                hintText: 'What do you like shooting?',
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('profile_city'),
              controller: _city,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Home city'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: 12.5,
                ),
              ),
            ],
            const SizedBox(height: 16),
            PressButton(
              semanticLabel: 'Save profile',
              onTap: _save,
              child: Container(
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.action,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Save',
                  style: TextStyle(
                    color: AppColors.onAction,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
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

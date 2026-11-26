import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../data/supabase_repository.dart';
import '../services/update_service.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'plan_trip_screen.dart';

/// Profile: avatar, stats, and working account/preferences rows.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tagCount = state.spots.expand((spot) => spot.tags).toSet().length;

    return Scaffold(
      body: SafeArea(
        child: ResponsiveBody(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 130),
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: PressButton(
                  semanticLabel: 'Open settings',
                  onTap: () => _showPreferences(context),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0x14FFFFFF),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: const Icon(Icons.settings_rounded,
                        color: AppColors.textPrimary, size: 21),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.hairline, width: 2),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF2A2A2E), Color(0xFF141416)],
                        ),
                      ),
                      child: const Icon(Icons.person_rounded,
                          color: AppColors.textPrimary, size: 42),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      AppInfo.handle,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Explorer · ${state.spots.length} places',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  _Stat('${state.viewedCount}', 'Visited'),
                  _Stat('${state.savedSpots.length}', 'Saved'),
                  _Stat('$tagCount', 'Collections'),
                ],
              ),
              const SizedBox(height: 24),
              _RowTile(
                icon: Icons.collections_bookmark_rounded,
                title: 'My Collections',
                trailing: '${state.savedSpots.length}',
                onTap: () => Navigator.of(context)
                    .push(AppMotion.slideUp(const PlanTripScreen())),
              ),
              const SizedBox(height: 10),
              _RowTile(
                icon: Icons.tune_rounded,
                title: 'Preferences',
                onTap: () => _showPreferences(context),
              ),
              const SizedBox(height: 10),
              _RowTile(
                icon: Icons.info_outline_rounded,
                title: 'App Settings',
                onTap: () => _showAppSettings(context),
              ),
              const SizedBox(height: 30),
              Center(
                child: Text(
                  '${AppInfo.name} v${AppInfo.version}',
                  style: const TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 11.5,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPreferences(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _PreferencesSheet(),
    );
  }

  Future<void> _showAppSettings(BuildContext context) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final usingSupabase = state.repository is SupabaseSpotRepository;

    final check = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'App Settings',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            fontFamily: 'Inter',
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SettingLine('Version', AppInfo.version),
            const SizedBox(height: 8),
            _SettingLine(
              'Data source',
              usingSupabase ? 'Supabase' : 'Demo seed data',
            ),
            const SizedBox(height: 8),
            const _SettingLine('Release channel', 'GitHub releases'),
            const SizedBox(height: 14),
            const Text(
              'Builds check the public release channel on launch and offer an '
              'upgrade when a newer version is published.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                height: 1.45,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await launchUrl(AppInfo.repoPage);
              } catch (_) {
                // Ignore launch failures; the version is still visible.
              }
            },
            child: const Text(
              'GitHub',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.action,
              foregroundColor: AppColors.onAction,
            ),
            child: const Text(
              'Check for updates',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );

    if (check != true) return;
    final release = await UpdateService.check();
    if (!context.mounted) return;

    if (release == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'You are on the latest version (${AppInfo.version}).',
          ),
        ),
      );
      return;
    }

    final update = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Version ${release.version} is available'),
        content: Text(
          release.notes.isEmpty
              ? 'A newer release is ready on GitHub.'
              : release.notes,
          style: const TextStyle(
            color: AppColors.textSecondary,
            height: 1.45,
            fontFamily: 'Inter',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.action,
              foregroundColor: AppColors.onAction,
            ),
            child: const Text('Open release'),
          ),
        ],
      ),
    );

    if (update == true) {
      try {
        await launchUrl(
          release.pageUrl,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        messenger.showSnackBar(
          SnackBar(content: SelectableText(release.pageUrl.toString())),
        );
      }
    }
  }
}

class _SettingLine extends StatelessWidget {
  const _SettingLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              fontFamily: 'Inter',
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              fontFamily: 'Inter',
            ),
          ),
        ),
      ],
    );
  }
}

class _PreferencesSheet extends StatelessWidget {
  const _PreferencesSheet();

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsState>(
      builder: (context, settings, _) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Preferences',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Changes apply immediately and are saved on this device.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 12),
                _SwitchRow(
                  title: 'Check for updates on launch',
                  subtitle: 'Show a prompt when a newer release exists',
                  value: settings.checkUpdates,
                  onChanged: settings.setCheckUpdates,
                ),
                _SwitchRow(
                  title: 'Metric distances',
                  subtitle: 'Kilometres instead of miles',
                  value: settings.metricUnits,
                  onChanged: settings.setMetricUnits,
                ),
                _SwitchRow(
                  title: 'Photo map pins',
                  subtitle: 'Show spot photos inside map pins',
                  value: settings.mapPhotoPins,
                  onChanged: settings.setMapPhotoPins,
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      activeThumbColor: AppColors.action,
      activeTrackColor: AppColors.success,
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter',
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11.5,
          fontFamily: 'Inter',
        ),
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({
    required this.icon,
    required this.title,
    this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.textSecondary, size: 19),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
              if (trailing != null)
                Text(
                  trailing!,
                  style: const TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Inter',
                  ),
                ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textFaint, size: 19),
            ],
          ),
        ),
      ),
    );
  }
}

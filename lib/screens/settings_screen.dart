import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../map/tile_sources.dart';
import '../services/update_service.dart';
import '../state/app_state.dart';
import '../state/location_outcome.dart';
import '../state/settings_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import '../widgets/location_prompt.dart';
import '../widgets/update_sheet.dart';

/// The single place for every app-level preference. Grouped by what the
/// setting affects, not by implementation detail.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    final app = context.watch<AppState>();
    final theme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            _Section(
              title: 'Map',
              children: [
                for (final style in [
                  TileSources.dark,
                  TileSources.street,
                  TileSources.carto(settings.cartoApiKey),
                ])
                  _SelectRow(
                    label: style.label,
                    selected: settings.mapStyle == style.id,
                    onTap: () => settings.setMapStyle(style.id),
                  ),
                if (settings.cartoApiKey.isEmpty) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 14),
                    child: Text(
                      'Paste a CARTO API key to use this style.',
                      style: theme.bodySmall?.copyWith(color: AppColors.danger),
                    ),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextField(
                    key: const ValueKey('carto_key_field'),
                    onChanged: settings.setCartoApiKey,
                    decoration: const InputDecoration(
                      labelText: 'CARTO API key',
                      hintText: 'Paste your key',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _SwitchRow(
                  title: 'Photo map pins',
                  subtitle: 'Show spot photos inside map pins',
                  value: settings.mapPhotoPins,
                  onChanged: settings.setMapPhotoPins,
                ),
              ],
            ),
            _Section(
              title: 'Distances',
              children: [
                _SwitchRow(
                  title: 'Metric distances',
                  subtitle: 'Kilometres instead of miles',
                  value: settings.metricUnits,
                  onChanged: settings.setMetricUnits,
                ),
              ],
            ),
            _Section(
              title: 'Updates',
              children: [
                _SwitchRow(
                  title: 'Check for updates on launch',
                  subtitle: 'Show a prompt when a newer release exists',
                  value: settings.checkUpdates,
                  onChanged: settings.setCheckUpdates,
                ),
                _ActionRow(
                  icon: Icons.system_update_rounded,
                  label: 'Check now',
                  onTap: () => _checkNow(context),
                ),
                _InfoRow(label: 'Version', value: AppInfo.version),
              ],
            ),
            _Section(
              title: 'Location',
              children: [
                _InfoRow(
                  label: 'Status',
                  value: _locationStatus(app.lastLocationOutcome),
                ),
                _ActionRow(
                  icon: Icons.location_on_outlined,
                  label: 'Manage location',
                  onTap: () => showLocationRecovery(
                    context,
                    app.lastLocationOutcome ?? LocationOutcome.failed,
                  ),
                ),
              ],
            ),
            _Section(
              title: 'About',
              children: [
                _InfoRow(label: 'Release channel', value: 'GitHub releases'),
                _InfoRow(
                  label: 'Data source',
                  value: AppInfo.backendConfigured ? 'Supabase' : 'Demo',
                ),
                _ActionRow(
                  icon: Icons.open_in_new_rounded,
                  label: 'Repository',
                  onTap: () => _openRepository(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _locationStatus(LocationOutcome? outcome) => switch (outcome) {
        LocationOutcome.granted || null => 'Ready',
        LocationOutcome.servicesOff => 'Services off',
        LocationOutcome.blocked => 'Blocked',
        LocationOutcome.denied => 'Not granted',
        LocationOutcome.failed => 'Unavailable',
      };

  Future<void> _checkNow(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final release = await UpdateService.check();
    if (!context.mounted) return;
    if (release == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('You are on the latest version.')),
      );
      return;
    }
    await showUpdateSheet(context, release);
  }

  Future<void> _openRepository(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final opened = await launchUrl(
        AppInfo.releasesPage,
        mode: LaunchMode.externalApplication,
      );
      if (!opened && context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: SelectableText(AppInfo.releasesPage.toString()),
          ),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: SelectableText(AppInfo.releasesPage.toString())),
      );
    }
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(AppLayout.radiusCard),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled row that selects one basemap style.
class _SelectRow extends StatelessWidget {
  const _SelectRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      child: PressButton(
        onTap: onTap,
        child: SizedBox(
          height: AppLayout.minTapTarget,
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? AppColors.accent : AppColors.textFaint,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: theme.bodyLarge?.copyWith(
                    color: selected ? AppColors.textPrimary : AppColors.textSecondary,
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
    final theme = Theme.of(context).textTheme;
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      activeThumbColor: AppColors.textPrimary,
      activeTrackColor: AppColors.accent,
      title: Text(title, style: theme.bodyLarge),
      subtitle: Text(subtitle, style: theme.bodySmall),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: label,
      child: PressButton(
        onTap: onTap,
        child: SizedBox(
          height: AppLayout.minTapTarget,
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(icon, color: AppColors.textSecondary, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: theme.bodyLarge)),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textFaint,
                size: 18,
              ),
              const SizedBox(width: 10),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Text(label, style: theme.bodyMedium),
          const Spacer(),
          Text(
            value,
            style: theme.bodyMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

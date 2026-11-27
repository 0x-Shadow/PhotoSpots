import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../map/tile_sources.dart';
import '../screens/auth_screen.dart';
import '../screens/legal_screen.dart';
import '../services/update_service.dart';
import '../state/app_state.dart';
import '../state/auth_state.dart';
import '../state/location_outcome.dart';
import '../state/settings_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/validators.dart';
import '../widgets/edit_profile_sheet.dart';
import '../widgets/location_prompt.dart';
import '../widgets/update_sheet.dart';

/// Complete app settings: profile editing, account & security controls,
/// feed algorithm preferences, map & display controls, permissions, and
/// Google Play legal / data safety requirements.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _cartoController;
  bool _obscureCarto = true;

  @override
  void initState() {
    super.initState();
    final initialKey = context.read<SettingsState>().cartoApiKey;
    _cartoController = TextEditingController(text: initialKey);
  }

  @override
  void dispose() {
    _cartoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    final app = context.watch<AppState>();
    final auth = context.watch<AuthState>();
    final theme = Theme.of(context).textTheme;

    if (_cartoController.text != settings.cartoApiKey &&
        _cartoController.text.trim() != settings.cartoApiKey) {
      _cartoController.text = settings.cartoApiKey;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ResponsiveBody(
          maxWidth: 680,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
            children: [
              _Section(
                title: 'Account',
                children: auth.isSignedIn
                    ? [
                        _InfoRow(label: 'Status', value: auth.statusLabel),
                        _InfoRow(label: 'Email', value: auth.email),
                        _InfoRow(
                          label: 'Display name',
                          value: auth.displayName,
                        ),
                        if (auth.city.isNotEmpty)
                          _InfoRow(label: 'Home city', value: auth.city),
                        _ActionRow(
                          icon: Icons.edit_outlined,
                          label: 'Edit profile',
                          subtitle: 'Name, bio, home city, and photo',
                          onTap: () => showEditProfileSheet(context),
                        ),
                        _ActionRow(
                          icon: Icons.lock_reset_rounded,
                          label: 'Change password',
                          onTap: () => _changePassword(context, auth),
                        ),
                        _ActionRow(
                          icon: Icons.logout_rounded,
                          label: 'Sign out',
                          onTap: () async {
                            await auth.signOut();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Signed out.')),
                            );
                          },
                        ),
                        if (app.blockedUserIds.isNotEmpty)
                          _ActionRow(
                            icon: Icons.block_rounded,
                            label:
                                'Blocked users (${app.blockedUserIds.length})',
                            onTap: () => _manageBlockedUsers(context, app),
                          ),
                      ]
                    : [
                        const _GuestAccountMessage(),
                        if (AuthState.supportsAccounts)
                          _ActionRow(
                            icon: Icons.person_add_alt_1_rounded,
                            label: 'Sign in or create account',
                            subtitle:
                                'Publish spots, comment, and sync your saves',
                            onTap: () => Navigator.of(context)
                                .push(AppMotion.slideUp(const AuthScreen())),
                          ),
                      ],
              ),
              _Section(
                title: 'Feed & Algorithm',
                children: [
                  _SwitchRow(
                    title: 'Personalized recommendations',
                    subtitle:
                        'Blend your saves, likes, and shooting light timing',
                    value: settings.personalizeFeed,
                    onChanged: settings.setPersonalizeFeed,
                  ),
                  _ActionRow(
                    icon: Icons.sort_rounded,
                    label: 'Default map sort',
                    subtitle: _sortLabel(settings.defaultMapSort),
                    onTap: () => _chooseDefaultSort(context, settings),
                  ),
                  _InfoRow(
                    label: 'Learned from',
                    value:
                        '${app.savedIds.length} saves · '
                        '${app.likedCount} likes · '
                        '${app.viewedCount} views',
                  ),
                  _InfoRow(
                    label: 'Top interest',
                    value: app.topInterests.isEmpty
                        ? 'Not enough activity yet'
                        : app.topInterests.first,
                  ),
                  _ActionRow(
                    icon: Icons.restart_alt_rounded,
                    label: 'Clear view history',
                    onTap: () async {
                      await app.clearViewHistory();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('View history cleared.')),
                      );
                    },
                  ),
                ],
              ),
              _Section(
                title: 'Map & Display',
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
                      padding: const EdgeInsets.only(left: 14, right: 14),
                      child: Text(
                        'Paste a CARTO API key to use this style.',
                        style: theme.bodySmall?.copyWith(
                          color: AppColors.danger,
                        ),
                      ),
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                    child: TextField(
                      key: const ValueKey('carto_key_field'),
                      controller: _cartoController,
                      obscureText: _obscureCarto,
                      onChanged: settings.setCartoApiKey,
                      decoration: InputDecoration(
                        labelText: 'CARTO API key',
                        hintText: 'Paste your key',
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: _obscureCarto ? 'Show key' : 'Hide key',
                              onPressed: () => setState(
                                () => _obscureCarto = !_obscureCarto,
                              ),
                              icon: Icon(
                                _obscureCarto
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                                size: 18,
                              ),
                            ),
                            if (settings.cartoApiKey.isNotEmpty)
                              IconButton(
                                tooltip: 'Clear key',
                                onPressed: () {
                                  _cartoController.clear();
                                  settings.setCartoApiKey('');
                                  if (settings.mapStyle == 'carto') {
                                    settings.setMapStyle('dark');
                                  }
                                },
                                icon: const Icon(Icons.close_rounded, size: 18),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  _SwitchRow(
                    title: 'Photo map pins',
                    subtitle: 'Show spot photos inside map pins',
                    value: settings.mapPhotoPins,
                    onChanged: settings.setMapPhotoPins,
                  ),
                  _SwitchRow(
                    title: 'Cluster nearby pins',
                    subtitle: 'Group pins when zoomed out for smoother zooming',
                    value: settings.clusterMapPins,
                    onChanged: settings.setClusterMapPins,
                  ),
                  _SwitchRow(
                    title: 'Metric distances',
                    subtitle: 'Kilometres instead of miles',
                    value: settings.metricUnits,
                    onChanged: settings.setMetricUnits,
                  ),
                ],
              ),
              _Section(
                title: 'Permissions & Storage',
                children: [
                  _InfoRow(
                    label: 'Location',
                    value: _locationStatus(app.lastLocationOutcome),
                  ),
                  _ActionRow(
                    icon: Icons.location_on_outlined,
                    label: 'Manage location',
                    onTap: () =>
                        runLocationFlow(context, explain: false, appState: app),
                  ),
                  _ActionRow(
                    icon: Icons.phonelink_setup_rounded,
                    label: 'System app permissions',
                    subtitle: 'Camera, photos, and location in OS settings',
                    onTap: () async {
                      await Geolocator.openAppSettings();
                    },
                  ),
                  _ActionRow(
                    icon: Icons.cleaning_services_outlined,
                    label: 'Clear cached images',
                    onTap: () {
                      PaintingBinding.instance.imageCache.clear();
                      PaintingBinding.instance.imageCache.clearLiveImages();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Image cache cleared.')),
                      );
                    },
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
                title: 'Data, Privacy & Legal',
                children: [
                  _ActionRow(
                    icon: Icons.privacy_tip_outlined,
                    label: 'Privacy Policy',
                    onTap: () => Navigator.of(context).push(
                      AppMotion.slideUp(
                        const LegalScreen(doc: LegalDoc.privacy),
                      ),
                    ),
                  ),
                  _ActionRow(
                    icon: Icons.gavel_rounded,
                    label: 'Terms of Service',
                    onTap: () => Navigator.of(context).push(
                      AppMotion.slideUp(const LegalScreen(doc: LegalDoc.terms)),
                    ),
                  ),
                  _ActionRow(
                    icon: Icons.shield_outlined,
                    label: 'Community Guidelines',
                    onTap: () => Navigator.of(context).push(
                      AppMotion.slideUp(
                        const LegalScreen(doc: LegalDoc.guidelines),
                      ),
                    ),
                  ),
                  _ActionRow(
                    icon: Icons.download_outlined,
                    label: 'Export my data',
                    subtitle: 'Copy a JSON summary of your profile & activity',
                    onTap: () => _exportData(context, app, auth),
                  ),
                  _ActionRow(
                    icon: Icons.description_outlined,
                    label: 'Open-source licenses',
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: AppInfo.name,
                      applicationVersion: AppInfo.version,
                    ),
                  ),
                  if (auth.isSignedIn)
                    _ActionRow(
                      icon: Icons.delete_forever_outlined,
                      label: 'Delete account',
                      subtitle: 'Permanently remove your account and data',
                      danger: true,
                      onTap: () => _deleteAccount(context, auth, app),
                    ),
                ],
              ),
              _Section(
                title: 'Support & About',
                children: [
                  _InfoRow(
                    label: 'Data source',
                    value: AppInfo.backendConfigured ? 'Supabase' : 'Demo',
                  ),
                  _ActionRow(
                    icon: Icons.mail_outline_rounded,
                    label: 'Contact support',
                    subtitle: AppInfo.supportEmail,
                    onTap: () => _openSupport(context),
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
      ),
    );
  }

  static String _sortLabel(String id) => switch (id) {
    'nearest' => 'Nearest',
    'top_rated' => 'Top rated',
    'saved' => 'Most saved',
    _ => 'Recommended for you',
  };

  static String _locationStatus(LocationOutcome? outcome) => switch (outcome) {
    LocationOutcome.granted => 'Ready',
    null => 'Not requested yet',
    LocationOutcome.servicesOff => 'Services off',
    LocationOutcome.blocked => 'Blocked',
    LocationOutcome.denied => 'Not granted',
    LocationOutcome.failed => 'Unavailable',
  };

  Future<void> _chooseDefaultSort(
    BuildContext context,
    SettingsState settings,
  ) async {
    const options = [
      ('recommended', 'Recommended for you'),
      ('nearest', 'Nearest'),
      ('top_rated', 'Top rated'),
      ('saved', 'Most saved'),
    ];
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Default map sort',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            for (final opt in options)
              ListTile(
                onTap: () => Navigator.of(sheetContext).pop(opt.$1),
                title: Text(
                  opt.$2,
                  style: TextStyle(
                    color: settings.defaultMapSort == opt.$1
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontWeight: settings.defaultMapSort == opt.$1
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
                trailing: settings.defaultMapSort == opt.$1
                    ? const Icon(Icons.check_rounded, color: AppColors.accent)
                    : null,
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (picked != null) {
      await settings.setDefaultMapSort(picked);
    }
  }

  Future<void> _changePassword(BuildContext context, AuthState auth) async {
    final controller = TextEditingController();
    String? error;
    final newPass = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Change password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New password',
                  hintText: '8+ characters, letters and numbers',
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 12),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final err = Validators.password(controller.text);
                if (err != null) {
                  setDialogState(() => error = err);
                  return;
                }
                Navigator.of(dialogContext).pop(controller.text);
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (newPass == null || !context.mounted) return;
    final res = await auth.updatePassword(newPass);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(res.message ?? 'Done.')));
  }

  Future<void> _manageBlockedUsers(BuildContext context, AppState app) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final blocked = app.blockedUserIds.toList();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Blocked users',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (blocked.isEmpty)
                    const Text(
                      'No blocked users.',
                      style: TextStyle(color: AppColors.textSecondary),
                    )
                  else
                    for (final id in blocked)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'User ${id.length > 8 ? id.substring(0, 8) : id}',
                          style: const TextStyle(color: AppColors.textPrimary),
                        ),
                        trailing: TextButton(
                          onPressed: () async {
                            await app.unblockUser(id);
                            setSheetState(() {});
                          },
                          child: const Text('Unblock'),
                        ),
                      ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _exportData(
    BuildContext context,
    AppState app,
    AuthState auth,
  ) async {
    final json = app.exportDataSummaryJson(
      displayName: auth.displayName,
      email: auth.email,
      bio: auth.bio,
      city: auth.city,
    );
    await Clipboard.setData(ClipboardData(text: json));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Your data summary JSON was copied to the clipboard.'),
      ),
    );
  }

  Future<void> _deleteAccount(
    BuildContext context,
    AuthState auth,
    AppState app,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your account, profile, saved list, likes, '
          'and comments. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep account'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final res = await auth.deleteAccount();
    if (!context.mounted) return;
    if (res.success) {
      await app.clearAllLocalActivity();
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(res.message ?? 'Account deleted.')));
  }

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
    final action = await showUpdateSheet(context, release);
    if (!context.mounted) return;
    await handleUpdateAction(context, release, action);
  }

  Future<void> _openSupport(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: AppInfo.supportEmail,
      queryParameters: {
        'subject': '${AppInfo.name} v${AppInfo.version} support',
      },
    );
    try {
      final opened = await launchUrl(uri);
      if (opened || !context.mounted) return;
    } catch (_) {}
    if (!context.mounted) return;
    await Clipboard.setData(const ClipboardData(text: AppInfo.supportEmail));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Support email copied: ${AppInfo.supportEmail}'),
      ),
    );
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
          SnackBar(content: SelectableText(AppInfo.releasesPage.toString())),
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
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: AppColors.textSecondary),
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
                    color: selected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
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
    this.subtitle,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final tint = danger ? AppColors.danger : AppColors.textSecondary;
    return Semantics(
      button: true,
      label: label,
      child: PressButton(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppLayout.minTapTarget),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(icon, color: tint, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: theme.bodyLarge?.copyWith(
                        color: danger ? AppColors.danger : null,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodySmall,
                      ),
                  ],
                ),
              ),
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

class _GuestAccountMessage extends StatelessWidget {
  const _GuestAccountMessage();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You’re browsing as a guest',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'No profile details are stored or shown until you sign in.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.bodyMedium),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

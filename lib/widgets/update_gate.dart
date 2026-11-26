import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../services/update_service.dart';
import '../state/settings_state.dart';
import '../theme/app_theme.dart';

/// Checks the release channel shortly after launch and offers an upgrade when a
/// newer release exists.
///
/// "Later" snoozes that release for 24 hours so the prompt stays useful without
/// nagging on every cold start. Updating opens the release page.
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  static const _snoozeVersionKey = 'update_snooze_version';
  static const _snoozeUntilKey = 'update_snooze_until';
  static const _snoozeFor = Duration(hours: 24);

  bool _started = false;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    if (_started) return;
    _started = true;

    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return;
    }

    if (prefs.getBool(SettingsState.checkUpdatesKey) == false) return;

    final release = await UpdateService.check();
    if (!mounted || release == null) return;

    final snoozedVersion = prefs.getString(_snoozeVersionKey);
    final snoozeUntilMs = prefs.getInt(_snoozeUntilKey) ?? 0;
    final snoozedUntil =
        DateTime.fromMillisecondsSinceEpoch(snoozeUntilMs);
    final isSnoozed = snoozedVersion == release.tag &&
        DateTime.now().isBefore(snoozedUntil);
    if (isSnoozed) return;

    await _showPrompt(release, prefs);
  }

  Future<void> _showPrompt(
    ReleaseInfo release,
    SharedPreferences prefs,
  ) async {
    if (_dialogOpen) return;
    _dialogOpen = true;

    final messenger = ScaffoldMessenger.maybeOf(context);
    final update = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _UpdateDialog(release: release),
    );

    _dialogOpen = false;

    if (update == true) {
      var opened = false;
      try {
        opened = await launchUrl(
          release.pageUrl,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        opened = false;
      }
      if (!opened) {
        try {
          opened = await launchUrl(release.pageUrl);
        } catch (_) {
          opened = false;
        }
      }
      if (!opened) {
        messenger?.showSnackBar(
          SnackBar(
            content: SelectableText(
              'Open ${release.pageUrl} to download version ${release.version}.',
            ),
          ),
        );
      }
      return;
    }

    // Dismissed or "Later": remind again tomorrow, or immediately if an even
    // newer release ships before the snooze expires.
    try {
      await prefs.setString(_snoozeVersionKey, release.tag);
      await prefs.setInt(
        _snoozeUntilKey,
        DateTime.now().add(_snoozeFor).millisecondsSinceEpoch,
      );
    } catch (_) {
      // Snoozing is best effort.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog({required this.release});

  final ReleaseInfo release;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final notes = release.notes.isEmpty
        ? 'Bug fixes and polish. No release notes were provided.'
        : release.notes;

    return AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: AppColors.hairline),
      ),
      title: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: AppColors.accentSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.system_update_rounded,
                color: AppColors.accent, size: 21),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Update available',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                fontFamily: 'Inter',
                letterSpacing: -0.4,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: media.width > 480 ? 380 : media.width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${AppInfo.name} ${release.version} is ready. '
              'You are on ${AppInfo.version}.',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                height: 1.45,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Text(
                  notes,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.5,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Release ${release.tag}',
              style: const TextStyle(
                color: AppColors.textFaint,
                fontSize: 11.5,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(
            'Later',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 6),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.action,
            foregroundColor: AppColors.onAction,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text(
            'Update',
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

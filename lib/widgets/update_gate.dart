import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../services/apk_installer.dart';
import '../services/update_service.dart';
import '../state/settings_state.dart';
import '../theme/app_theme.dart';

/// Checks the release channel shortly after launch and offers an upgrade when a
/// newer release exists.
///
/// On Android the update is downloaded and handed to the system installer from
/// inside the app. Everywhere else (and when a release has no APK attached) the
/// release page opens instead. "Later" snoozes that release for 24 hours so the
/// prompt stays useful without nagging on every cold start.
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
    final action = await showDialog<_UpdateAction>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _UpdateDialog(release: release),
    );

    _dialogOpen = false;

    if (action == _UpdateAction.installStarted) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Follow the prompts to finish installing the update.',
          ),
        ),
      );
      return;
    }

    if (action == _UpdateAction.openPage) {
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

enum _UpdateAction { installStarted, openPage }

enum _Phase { idle, downloading, installing, needsPermission, failed }

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.release});

  final ReleaseInfo release;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  _Phase _phase = _Phase.idle;
  int _received = 0;
  int? _total;
  String? _error;
  String? _apkPath;
  bool _cancelRequested = false;

  /// Android can install its own update only when the release ships an APK.
  bool get _canSelfUpdate =>
      ApkInstaller.isSupported && widget.release.canSelfUpdate;

  bool get _busy =>
      _phase == _Phase.downloading || _phase == _Phase.installing;

  double? get _progress {
    final total = _total;
    if (total == null || total <= 0) return null;
    return (_received / total).clamp(0.0, 1.0);
  }

  Future<void> _startUpdate() async {
    if (!_canSelfUpdate) {
      Navigator.of(context).pop(_UpdateAction.openPage);
      return;
    }

    // A previous attempt may have downloaded the package already, for example
    // when the install permission was still missing.
    if (_apkPath != null) {
      await _install();
      return;
    }

    setState(() {
      _phase = _Phase.downloading;
      _received = 0;
      _total = widget.release.apkSize;
      _error = null;
      _cancelRequested = false;
    });

    try {
      final dir = await getTemporaryDirectory();
      final target =
          File('${dir.path}/photospot-${widget.release.version}.apk');
      final file = await UpdateService.downloadApk(
        widget.release,
        target: target,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total;
          });
        },
        isCancelled: () => _cancelRequested,
      );

      if (!mounted) return;
      _apkPath = file.path;
      await _install();
    } on UpdateDownloadException catch (error) {
      if (!mounted) return;
      if (error.isCancelled) {
        setState(() => _phase = _Phase.idle);
        return;
      }
      setState(() {
        _phase = _Phase.failed;
        _error = _message(error);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = 'The update could not be downloaded. Please try again.';
      });
    }
  }

  Future<void> _install() async {
    final path = _apkPath;
    if (path == null) return;

    setState(() => _phase = _Phase.installing);

    if (!await ApkInstaller.canInstall()) {
      await ApkInstaller.requestInstallPermission();
      if (!mounted) return;
      if (!await ApkInstaller.canInstall()) {
        setState(() => _phase = _Phase.needsPermission);
        return;
      }
    }

    final started = await ApkInstaller.install(path);
    if (!mounted) return;

    if (started) {
      Navigator.of(context).pop(_UpdateAction.installStarted);
      return;
    }

    setState(() {
      _phase = _Phase.failed;
      _error = 'Android could not open the installer for this update.';
    });
  }

  String _message(UpdateDownloadException error) {
    if (error.reason == 'status-404' || error.reason == 'status-403') {
      return 'This release cannot be downloaded automatically. '
          'Open the release page instead.';
    }
    if (error.reason == 'incomplete') {
      return 'The download was interrupted. Please try again.';
    }
    return 'The update could not be downloaded. Check your connection and '
        'try again.';
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);

    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
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
                '${AppInfo.name} ${widget.release.version} is ready. '
                'You are on ${AppInfo.version}.',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                  fontFamily: 'Inter',
                ),
              ),
              if (_phase == _Phase.downloading) ...[
                const SizedBox(height: 18),
                _DownloadProgress(
                  progress: _progress,
                  received: _received,
                  total: _total,
                ),
              ] else if (_phase == _Phase.installing) ...[
                const SizedBox(height: 18),
                const Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accent,
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Opening the installer…',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Text(
                      widget.release.notes.isEmpty
                          ? 'Bug fixes and polish. '
                              'No release notes were provided.'
                          : widget.release.notes,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.5,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                ),
                if (_phase == _Phase.failed && _error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 13,
                      height: 1.45,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
                if (_phase == _Phase.needsPermission) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Allow PhotoSpot to install updates, then tap '
                    '“Install update” again. The download is already saved, so '
                    'nothing is fetched twice.',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.45,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  'Release ${widget.release.tag}',
                  style: const TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 11.5,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        actions: _actions(),
      ),
    );
  }

  List<Widget> _actions() {
    if (_phase == _Phase.downloading) {
      return [
        TextButton(
          onPressed: () => setState(() => _cancelRequested = true),
          child: const Text(
            'Cancel',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ];
    }

    if (_phase == _Phase.installing) {
      return const [SizedBox.shrink()];
    }

    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text(
          'Later',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      if (_phase == _Phase.failed)
        TextButton(
          onPressed: () => Navigator.of(context).pop(_UpdateAction.openPage),
          child: const Text(
            'Release page',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      const SizedBox(width: 6),
      FilledButton.icon(
        onPressed: _startUpdate,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.action,
          foregroundColor: AppColors.onAction,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: Icon(
          _phase == _Phase.needsPermission
              ? Icons.settings_rounded
              : Icons.download_rounded,
          size: 18,
        ),
        label: Text(
          _phase == _Phase.needsPermission
              ? 'Install update'
              : _canSelfUpdate
                  ? 'Update'
                  : 'Get update',
          style: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ];
  }
}

class _DownloadProgress extends StatelessWidget {
  const _DownloadProgress({
    required this.progress,
    required this.received,
    required this.total,
  });

  final double? progress;
  final int received;
  final int? total;

  @override
  Widget build(BuildContext context) {
    final total = this.total;
    final label = total == null
        ? '${_megabytes(received)} MB downloaded'
        : '${_megabytes(received)} of ${_megabytes(total)} MB';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: AppColors.hairline,
            valueColor: const AlwaysStoppedAnimation(AppColors.accent),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontFamily: 'Inter',
          ),
        ),
      ],
    );
  }

  static String _megabytes(int bytes) =>
      (bytes / (1024 * 1024)).toStringAsFixed(1);
}

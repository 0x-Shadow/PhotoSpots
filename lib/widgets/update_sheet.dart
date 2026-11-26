import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../app_info.dart';
import '../services/apk_installer.dart';
import '../services/update_service.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';

/// Where an update sheet ended, so the gate can keep owning snooze and
/// release-page orchestration.
enum UpdateAction { installStarted, openPage }

/// Phases of an in-app Android update. Kept public so the sheet can be shown
/// directly in tests without running a real download.
enum UpdatePhase { idle, downloading, installing, needsPermission, failed }

/// The single update UI: an in-app sheet used both by the launch gate and by
/// Settings → Check now.
Future<UpdateAction?> showUpdateSheet(
  BuildContext context,
  ReleaseInfo release, {
  bool? canInstall,
}) {
  return showModalBottomSheet<UpdateAction?>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: AppColors.surfaceElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => UpdateSheet(release: release, canInstall: canInstall),
  );
}

/// Presents an available release and drives the download/install flow.
/// Android can install its own update only when the release ships an APK;
/// everywhere else the action opens the release page.
class UpdateSheet extends StatefulWidget {
  const UpdateSheet({
    super.key,
    required this.release,
    this.canInstall,
    this.initialPhase = UpdatePhase.idle,
    this.initialReceived = 0,
    this.initialTotal,
  });

  final ReleaseInfo release;
  final bool? canInstall;

  /// Test hooks: let a phase be rendered without performing network work.
  final UpdatePhase initialPhase;
  final int initialReceived;
  final int? initialTotal;

  @override
  State<UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<UpdateSheet> {
  late UpdatePhase _phase;
  late int _received;
  int? _total;
  String? _error;
  String? _apkPath;
  bool _cancelRequested = false;

  @override
  void initState() {
    super.initState();
    _phase = widget.initialPhase;
    _received = widget.initialReceived;
    _total = widget.initialTotal;
  }

  bool get _selfUpdate =>
      widget.canInstall ?? (ApkInstaller.isSupported && widget.release.canSelfUpdate);

  bool get _busy =>
      _phase == UpdatePhase.downloading || _phase == UpdatePhase.installing;

  double? get _progress {
    final total = _total;
    if (total == null || total <= 0) return null;
    return (_received / total).clamp(0.0, 1.0);
  }

  Future<void> _startUpdate() async {
    if (!_selfUpdate) {
      Navigator.of(context).pop(UpdateAction.openPage);
      return;
    }

    // A previous attempt may have downloaded the package already, for example
    // when the install permission was still missing.
    if (_apkPath != null) {
      await _install();
      return;
    }

    setState(() {
      _phase = UpdatePhase.downloading;
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
        setState(() => _phase = UpdatePhase.idle);
        return;
      }
      setState(() {
        _phase = UpdatePhase.failed;
        _error = _message(error);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = UpdatePhase.failed;
        _error = 'The update could not be downloaded. Please try again.';
      });
    }
  }

  Future<void> _install() async {
    final path = _apkPath;
    if (path == null) return;

    setState(() => _phase = UpdatePhase.installing);

    if (!await ApkInstaller.canInstall()) {
      await ApkInstaller.requestInstallPermission();
      if (!mounted) return;
      if (!await ApkInstaller.canInstall()) {
        setState(() => _phase = UpdatePhase.needsPermission);
        return;
      }
    }

    final started = await ApkInstaller.install(path);
    if (!mounted) return;

    if (started) {
      Navigator.of(context).pop(UpdateAction.installStarted);
      return;
    }

    setState(() {
      _phase = UpdatePhase.failed;
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
    final theme = Theme.of(context).textTheme;

    return PopScope(
      canPop: !_busy,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            22,
            14,
            22,
            18 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: AppColors.accentSoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.system_update_rounded,
                      color: AppColors.accent,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Update available', style: theme.titleLarge),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '${AppInfo.name} ${widget.release.version} is ready. '
                'You are on ${AppInfo.version}.',
                style: theme.bodyLarge?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              if (_phase == UpdatePhase.downloading)
                _DownloadProgress(
                  progress: _progress,
                  received: _received,
                  total: _total,
                )
              else if (_phase == UpdatePhase.installing)
                Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Opening the installer…',
                        style: theme.bodyMedium,
                      ),
                    ),
                  ],
                )
              else ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: SingleChildScrollView(
                    child: Text(
                      widget.release.notes.isEmpty
                          ? 'Bug fixes and polish. No release notes were '
                              'provided.'
                          : widget.release.notes,
                      style: theme.bodyMedium,
                    ),
                  ),
                ),
                if (_phase == UpdatePhase.failed && _error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: theme.bodyMedium?.copyWith(color: AppColors.danger),
                  ),
                ],
                if (_phase == UpdatePhase.needsPermission) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Allow PhotoSpot to install updates, then tap Update again.',
                    style: theme.bodyMedium,
                  ),
                ],
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: _actions(theme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _actions(TextTheme theme) {
    final secondary = theme.labelLarge?.copyWith(
      color: AppColors.textSecondary,
      fontWeight: FontWeight.w600,
    );
    if (_phase == UpdatePhase.downloading) {
      return [
        TextButton(
          onPressed: () => setState(() => _cancelRequested = true),
          child: Text('Cancel', style: secondary),
        ),
      ];
    }
    if (_phase == UpdatePhase.installing) return [const SizedBox.shrink()];

    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text('Later', style: secondary),
      ),
      if (_phase == UpdatePhase.failed || !_selfUpdate)
        TextButton(
          onPressed: () => Navigator.of(context).pop(UpdateAction.openPage),
          child: Text('Release page', style: secondary),
        ),
      const SizedBox(width: 4),
      PressButton(
        semanticLabel: _phase == UpdatePhase.needsPermission
            ? 'Install update'
            : 'Update now',
        onTap: _startUpdate,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.action,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _phase == UpdatePhase.needsPermission
                ? 'Install update'
                : _selfUpdate
                    ? 'Update now'
                    : 'Get update',
            style: theme.labelLarge?.copyWith(
              color: AppColors.onAction,
              fontWeight: FontWeight.w800,
            ),
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
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  static String _megabytes(int bytes) =>
      (bytes / (1024 * 1024)).toStringAsFixed(1);
}

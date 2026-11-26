import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/update_service.dart';
import '../state/settings_state.dart';
import 'update_sheet.dart';

/// Checks the release channel shortly after launch and offers an upgrade when a
/// newer release exists.
///
/// Presentation lives in [showUpdateSheet]; this widget owns only when to
/// check, how long to snooze a release, and what to do with the sheet result.
/// "Later" snoozes that release for 24 hours so the prompt stays useful without
/// nagging on every cold start.
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
  bool _sheetOpen = false;

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
    final snoozedUntil = DateTime.fromMillisecondsSinceEpoch(snoozeUntilMs);
    final isSnoozed = snoozedVersion == release.tag &&
        DateTime.now().isBefore(snoozedUntil);
    if (isSnoozed) return;

    await _showPrompt(release, prefs);
  }

  Future<void> _showPrompt(ReleaseInfo release, SharedPreferences prefs) async {
    if (_sheetOpen) return;
    _sheetOpen = true;

    final messenger = ScaffoldMessenger.maybeOf(context);
    final action = await showUpdateSheet(context, release);

    _sheetOpen = false;

    if (action == UpdateAction.installStarted && !mounted) return;
    if (action == UpdateAction.installStarted) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Follow the prompts to finish installing the update.'),
        ),
      );
      return;
    }

    if (action == UpdateAction.openPage) {
      if (!mounted) return;
      await handleUpdateAction(context, release, action);
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

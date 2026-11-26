import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/location_outcome.dart';
import '../theme/app_theme.dart';

/// Asks once, in plain language, why the app wants location before showing
/// the OS permission dialog. Returns true when the user taps Allow.
Future<bool> showLocationRationale(BuildContext context) async {
  final answer = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.surfaceElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Why location?',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'PhotoSpot uses your location to sort spots by distance and '
              'centre the map on you.',
              style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 20),
            Semantics(
              button: true,
              child: InkWell(
                onTap: () => Navigator.of(sheetContext).pop(true),
                borderRadius: BorderRadius.circular(AppLayout.radiusCard),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.action,
                    borderRadius: BorderRadius.circular(AppLayout.radiusCard),
                  ),
                  child: Text(
                    'Allow',
                    style: Theme.of(sheetContext)
                        .textTheme
                        .labelLarge
                        ?.copyWith(
                          color: AppColors.onAction,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Semantics(
              button: true,
              child: InkWell(
                onTap: () => Navigator.of(sheetContext).pop(false),
                borderRadius: BorderRadius.circular(AppLayout.radiusCard),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  alignment: Alignment.center,
                  child: Text(
                    'Not now',
                    style: Theme.of(sheetContext)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return answer ?? false;
}

/// Shows the right recovery action for a failed location request.
///
/// A plain snackbar leaves blocked users stuck: "Location permission was
/// denied." tells them nothing about how to fix a permanent block. This sheet
/// names the outcome and opens the settings page that can actually fix it.
Future<void> showLocationRecovery(
  BuildContext context,
  LocationOutcome outcome, {
  VoidCallback? onRetry,
}) {
  final openSettings = outcome == LocationOutcome.blocked ||
      outcome == LocationOutcome.servicesOff;
  final title = openSettings
      ? 'Location needs your say-so'
      : 'Location unavailable';

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surfaceElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              locationMessage(outcome),
              style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 20),
            if (openSettings) ...[
              Semantics(
                button: true,
                child: InkWell(
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    if (outcome == LocationOutcome.servicesOff) {
                      Geolocator.openLocationSettings();
                    } else {
                      Geolocator.openAppSettings();
                    }
                  },
                  borderRadius: BorderRadius.circular(AppLayout.radiusCard),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.action,
                      borderRadius:
                          BorderRadius.circular(AppLayout.radiusCard),
                    ),
                    child: Text(
                      'Open settings',
                      style: Theme.of(sheetContext)
                          .textTheme
                          .labelLarge
                          ?.copyWith(
                            color: AppColors.onAction,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (!openSettings) ...[
              Semantics(
                button: true,
                child: InkWell(
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onRetry?.call();
                  },
                  borderRadius: BorderRadius.circular(AppLayout.radiusCard),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.action,
                      borderRadius: BorderRadius.circular(AppLayout.radiusCard),
                    ),
                    child: Text(
                      'Try again',
                      style: Theme.of(sheetContext)
                          .textTheme
                          .labelLarge
                          ?.copyWith(
                            color: AppColors.onAction,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Semantics(
              button: true,
              child: InkWell(
                onTap: () => Navigator.of(sheetContext).pop(),
                borderRadius: BorderRadius.circular(AppLayout.radiusCard),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  alignment: Alignment.center,
                  child: Text(
                    'Not now',
                    style: Theme.of(sheetContext)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// One entry point for a user-initiated location request: explain first when
/// permission is still undecided, ask the OS, then offer a recovery action for
/// outcomes that require the user to change a setting.
///
/// The two optional hooks are injectable for tests; production uses the real
/// permission check and [AppState.requestLocation].
Future<LocationOutcome> runLocationFlow(
  BuildContext context, {
  bool explain = true,
  AppState? appState,
  Future<bool> Function()? needsRationale,
  Future<LocationOutcome> Function()? request,
}) async {
  final undecided = needsRationale ??
      (() async => await Geolocator.checkPermission() == LocationPermission.denied);
  if (explain && await undecided()) {
    if (!context.mounted) return LocationOutcome.denied;
    if (!await showLocationRationale(context)) {
      if (appState != null) {
        appState.recordLocationOutcome(LocationOutcome.denied);
      }
      return LocationOutcome.denied;
    }
  }

  if (!context.mounted) return LocationOutcome.failed;
  final ask = request ?? (appState ?? context.read<AppState>()).requestLocation;
  final outcome = await ask();
  appState?.recordLocationOutcome(outcome);
  if (!context.mounted) return outcome;

  if (outcome == LocationOutcome.servicesOff ||
      outcome == LocationOutcome.blocked) {
    await showLocationRecovery(context, outcome);
  } else if (outcome == LocationOutcome.denied ||
      outcome == LocationOutcome.failed) {
    await showLocationRecovery(
      context,
      outcome,
      onRetry: () => runLocationFlow(context, explain: false, appState: appState),
    );
  }
  return outcome;
}

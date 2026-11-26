import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/spot.dart';
import '../state/app_state.dart';
import 'format.dart';

/// Toggles a bookmark and reports the real outcome.
Future<void> toggleSaveWithFeedback(BuildContext context, Spot spot) async {
  final state = context.read<AppState>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();

  final synced = await state.toggleSave(spot);
  final nowSaved = state.isSaved(spot.id);

  final message = synced
      ? (nowSaved ? 'Saved to your list' : 'Removed from saved')
      : (nowSaved
          ? 'Saved on this device only — syncing failed.'
          : "Couldn't update saved spots.");

  messenger?.showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
  );
}

/// Opens the platform maps app at the spot.
Future<void> openDirections(BuildContext context, Spot spot) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final uri = directionsUri(spot.location.latitude, spot.location.longitude);

  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (!opened) {
    try {
      opened = await launchUrl(uri);
    } catch (_) {
      opened = false;
    }
  }

  if (!opened) {
    messenger?.showSnackBar(
      SnackBar(content: SelectableText(uri.toString())),
    );
  }
}

/// Copies a map link for the spot to the clipboard.
Future<void> shareSpot(BuildContext context, Spot spot) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final uri = mapLinkUri(spot.location.latitude, spot.location.longitude);

  final label = StringBuffer(spot.title);
  if (spot.city.isNotEmpty) label.write(' · ${spot.city}');
  label.write('\n$uri');

  try {
    await Clipboard.setData(ClipboardData(text: label.toString()));
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('Spot link copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  } catch (_) {
    messenger?.showSnackBar(
      SnackBar(content: SelectableText(uri.toString())),
    );
  }
}

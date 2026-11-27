import 'package:flutter/material.dart';
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

/// Toggles a like and reports the real outcome.
Future<void> toggleLikeWithFeedback(BuildContext context, Spot spot) async {
  final state = context.read<AppState>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();

  final synced = await state.toggleLike(spot);
  final nowLiked = state.isLiked(spot.id);

  final message = synced
      ? (nowLiked ? 'Added to your likes' : 'Removed from your likes')
      : (nowLiked
          ? 'Liked on this device only — syncing failed.'
          : "Couldn't update likes.");

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


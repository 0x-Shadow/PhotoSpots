import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Shares a spot's exact location through the native share sheet.
///
/// The link opens the coordinates in Google Maps; if the platform share sheet
/// is unavailable the link is copied instead so the action still succeeds.
Future<void> shareLocationLink(
  BuildContext context, {
  required double lat,
  required double lng,
  required String title,
}) async {
  final uri = Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
  );
  final messenger = ScaffoldMessenger.maybeOf(context);
  var shared = false;
  try {
    await SharePlus.instance.share(
      ShareParams(text: '$title — $lat, $lng', uri: uri),
    );
    shared = true;
  } catch (_) {
    // Fall through to the clipboard.
  }
  if (!shared) {
    try {
      await Clipboard.setData(ClipboardData(text: uri.toString()));
      messenger?.showSnackBar(
        const SnackBar(content: Text('Link copied.')),
      );
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: SelectableText(uri.toString())),
      );
    }
  }
}

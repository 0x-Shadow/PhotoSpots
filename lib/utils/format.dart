/// Shared number/label formatting so cards, rows, and detail agree.
library;

import 'package:flutter/material.dart';

/// `12500` -> `12.5k`, `1200000` -> `1.2m`.
String formatCount(int value) {
  if (value < 1000) return '$value';
  if (value < 1000000) {
    final k = value / 1000;
    return '${k >= 100 ? k.round() : k.toStringAsFixed(1)}k';
  }
  final m = value / 1000000;
  return '${m.toStringAsFixed(1)}m';
}

/// Human distance, metric or imperial.
String formatDistance(double km, {bool metric = true}) {
  if (!metric) {
    final miles = km * 0.621371;
    if (miles < 0.1) return '${(miles * 5280).round()} ft';
    if (miles < 10) return '${miles.toStringAsFixed(1)} mi';
    return '${miles.round()} mi';
  }
  if (km < 1) return '${(km * 1000).round()} m';
  if (km < 10) return '${km.toStringAsFixed(1)} km';
  return '${km.round()} km';
}

/// Title-cases a single tag for display in a fact tile.
String titleCase(String value) {
  if (value.isEmpty) return value;
  return value
      .split(' ')
      .map((word) => word.isEmpty
          ? word
          : '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}

/// Builds a directions link that every platform's maps app can open.
Uri directionsUri(num latitude, num longitude) {
  return Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude',
  );
}

/// Builds a shareable link for a spot.
Uri mapLinkUri(num latitude, num longitude) {
  return Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
  );
}

const kContentMaxWidth = 760.0;
const kWideBreakpoint = 900.0;

/// Centers page content and caps its width on tablets and desktop windows.
class ResponsiveBody extends StatelessWidget {
  const ResponsiveBody({
    super.key,
    required this.child,
    this.maxWidth = kContentMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

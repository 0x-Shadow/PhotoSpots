import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/spot.dart';
import '../screens/spot_detail_screen.dart';
import '../state/app_state.dart';
import '../theme/app_animations.dart';

/// Opens a spot detail page, records the view, and optionally links a Hero.
Future<void> openSpot(
  BuildContext context,
  Spot spot, {
  String? heroTag,
}) {
  context.read<AppState>().recordView(spot);
  return Navigator.of(context).push(
    AppMotion.slideUp(
      SpotDetailScreen(spotId: spot.id, heroTag: heroTag),
    ),
  );
}

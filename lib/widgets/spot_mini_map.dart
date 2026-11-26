import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../map/map_tile_layers.dart';
import '../screens/root_shell.dart';
import '../state/settings_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';

/// A small, non-interactive map showing where a spot is. Tapping it opens the
/// full Map tab centred on the pin.
class SpotMiniMap extends StatelessWidget {
  const SpotMiniMap({
    super.key,
    required this.point,
    required this.label,
    this.height = 120,
  });

  final LatLng point;
  final String label;
  final double height;

  @override
  Widget build(BuildContext context) {
    final style = context.watch<SettingsState>().activeMapStyle;
    return Semantics(
      button: true,
      label: label,
      child: PressButton(
        semanticLabel: label,
        onTap: () {
          RootShell.openMapAt(point);
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppLayout.radiusCard),
          child: SizedBox(
            height: height,
            child: AbsorbPointer(
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: point,
                  initialZoom: 15,
                  interactionOptions:
                      const InteractionOptions(flags: InteractiveFlag.none),
                ),
                children: [
                  MapTileLayers(style: style, onFallback: (_) {}),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: point,
                        width: 32,
                        height: 32,
                        child: const Icon(
                          Icons.place_rounded,
                          color: AppColors.accent,
                          size: 30,
                          shadows: [
                            Shadow(
                              color: Color(0x66000000),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  MapAttribution(style: style),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

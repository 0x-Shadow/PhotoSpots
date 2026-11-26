import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../map/map_tile_layers.dart';
import '../map/tile_sources.dart';
import '../screens/root_shell.dart';
import '../state/settings_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';

/// A small, non-interactive map showing where a spot is. Tapping it opens the
/// full Map tab centred on the pin.
class SpotMiniMap extends StatefulWidget {
  const SpotMiniMap({
    super.key,
    required this.point,
    required this.label,
    this.height = 120,
    this.probe,
  });

  final LatLng point;
  final String label;
  final double height;

  /// Injectable for tests; production uses the shared tile probe.
  final Future<TileProbeResult> Function(MapStyle)? probe;

  @override
  State<SpotMiniMap> createState() => _SpotMiniMapState();
}

class _SpotMiniMapState extends State<SpotMiniMap> {
  bool _streetFallback = false;
  bool _failed = false;

  void _onFallback(String _) {
    if (_streetFallback) {
      if (!_failed) setState(() => _failed = true);
      return;
    }
    setState(() => _streetFallback = true);
  }

  @override
  Widget build(BuildContext context) {
    final preferred = context.watch<SettingsState>().activeMapStyle;
    final style = _streetFallback ? TileSources.street : preferred;

    return Semantics(
      button: true,
      label: widget.label,
      child: PressButton(
        semanticLabel: widget.label,
        onTap: () {
          RootShell.openMapAt(widget.point);
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppLayout.radiusCard),
          child: SizedBox(
            height: widget.height,
            child: AbsorbPointer(
              child: Stack(
                children: [
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: widget.point,
                      initialZoom: 15,
                      interactionOptions:
                          const InteractionOptions(flags: InteractiveFlag.none),
                    ),
                    children: [
                      MapTileLayers(
                        style: style,
                        onFallback: _onFallback,
                        probe: widget.probe,
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: widget.point,
                            width: 32,
                            height: 32,
                            child: const Icon(
                              Icons.place_rounded,
                              color: AppColors.accent,
                              size: 30,
                            ),
                          ),
                        ],
                      ),
                      MapAttribution(style: style),
                    ],
                  ),
                  if (_failed)
                    Positioned.fill(
                      child: Container(
                        color: AppColors.background.withValues(alpha: 0.85),
                        alignment: Alignment.center,
                        child: Text(
                          'Map unavailable',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

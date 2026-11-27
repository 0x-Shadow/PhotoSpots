import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import 'tile_sources.dart';

/// The basemap for a map widget: one or two stacked [TileLayer]s for
/// [MapTileLayers.style], plus a one-shot probe that tells the parent when the
/// source is unusable.
///
/// The probe exists because a refused basemap can answer HTTP 200 with an
/// image that is not a map (CARTO's "API KEY REQUIRED" watermark), so status
/// codes alone cannot keep that off the screen.
class MapTileLayers extends StatefulWidget {
  const MapTileLayers({
    super.key,
    required this.style,
    required this.onFallback,
    this.probe,
  });

  final MapStyle style;

  /// Called with a style id to switch to when the probe reports anything but
  /// a usable map. The parent switches styles; if the id it sends back is the
  /// one already active, every source has failed.
  final ValueChanged<String> onFallback;

  /// Injectable for tests; defaults to [probeTiles].
  final Future<TileProbeResult> Function(MapStyle)? probe;

  @override
  State<MapTileLayers> createState() => MapTileLayersState();
}

class MapTileLayersState extends State<MapTileLayers> {
  late MapStyle _style;

  @override
  void initState() {
    super.initState();
    _style = widget.style;
    _probe();
  }

  @override
  void didUpdateWidget(covariant MapTileLayers oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.style.urlTemplate != widget.style.urlTemplate) {
      _style = widget.style;
      _probe();
    }
  }

  Future<void> _probe() async {
    final probe = widget.probe ?? probeTiles;
    final result = await probe(_style);
    if (!mounted) return;
    if (result != TileProbeResult.ok) widget.onFallback('street');
  }

  /// Re-runs the probe, used by the failure panel's Retry action.
  Future<void> retry() => _probe();

  @override
  Widget build(BuildContext context) {
    // Only ask for @2x tiles when the server actually serves them. On a
    // template without `{r}` flutter_map "simulates" retina by loading the
    // next zoom level and scaling it down — four times the tiles and decode
    // work, which is what makes a phone map crawl. Esri and OSM have no @2x.
    final retina = RetinaMode.isHighDensity(context) &&
        _style.urlTemplate.contains('{r}');
    final base = TileLayer(
      urlTemplate: _style.urlTemplate,
      subdomains: _style.subdomains,
      userAgentPackageName: 'com.photospot.app',
      maxZoom: _style.maxZoom.toDouble(),
      retinaMode: retina,
    );
    final referenceUrl = _style.referenceUrlTemplate;

    // Positioned so the two layers stack inside FlutterMap's own layer stack;
    // each TileLayer applies the camera transform to itself.
    return Positioned.fill(
      child: Stack(
        children: [
          base,
          if (referenceUrl != null)
            TileLayer(
              urlTemplate: referenceUrl,
              userAgentPackageName: 'com.photospot.app',
              maxZoom: _style.maxZoom.toDouble(),
              retinaMode: retina,
            ),
        ],
      ),
    );
  }
}

/// Shown over the map when no configured style can render, so a dead basemap
/// reads as an actionable state instead of an empty black rectangle.
class MapUnavailableView extends StatelessWidget {
  const MapUnavailableView({
    super.key,
    required this.styleLabel,
    required this.onRetry,
  });

  final String styleLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppLayout.radiusCard),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              color: AppColors.textSecondary,
              size: 26,
            ),
            const SizedBox(height: 10),
            Text(
              'Map tiles unavailable',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              styleLabel,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            PressButton(
              semanticLabel: 'Retry',
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.action,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Retry',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.onAction,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Attribution for the active style: one entry per source in the style's
/// attribution line, each linking to its licence page.
class MapAttribution extends StatelessWidget {
  const MapAttribution({super.key, required this.style});

  final MapStyle style;

  static Uri? _urlFor(String source) {
    if (source.contains('OpenStreetMap')) {
      return Uri.parse('https://www.openstreetmap.org/copyright');
    }
    if (source.contains('CARTO')) return Uri.parse('https://carto.com/attributions');
    if (source.contains('Esri')) return Uri.parse('https://www.esri.com/');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final sources = style.attribution
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();

    return RichAttributionWidget(
      alignment: AttributionAlignment.bottomLeft,
      attributions: [
        for (final source in sources)
          if (_urlFor(source) case final url?)
            TextSourceAttribution(source, onTap: () => launchUrl(url))
          else
            TextSourceAttribution(source),
      ],
    );
  }
}

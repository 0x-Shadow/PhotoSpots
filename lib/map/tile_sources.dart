import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// A basemap style: the tile URL pattern plus everything the map needs to
/// render and attribute it. Nothing here requires an API key unless the style
/// says so, which is what keeps the default experience free.
class MapStyle {
  const MapStyle({
    required this.id,
    required this.label,
    required this.urlTemplate,
    this.subdomains = const [],
    required this.maxZoom,
    this.yBeforeX = false,
    required this.attribution,
    required this.requiresKey,
    this.referenceUrlTemplate,
  });

  /// Stable identifier persisted in settings (`dark`, `street`, `carto`).
  final String id;

  /// Human label for the settings picker.
  final String label;

  final String urlTemplate;

  /// `{s}` placeholders to rotate through; empty when the host has none.
  final List<String> subdomains;

  final int maxZoom;

  /// Esri orders its tiles `{z}/{y}/{x}`; everyone else uses `{z}/{x}/{y}`.
  final bool yBeforeX;

  /// Single comma-separated attribution line.
  final String attribution;

  /// True when tiles only render with a stored API key.
  final bool requiresKey;

  /// Optional label/road overlay stacked above the base layer.
  final String? referenceUrlTemplate;
}

/// The registry of basemaps the app can render without a paid account.
class TileSources {
  TileSources._();

  /// Esri's dark canvas: keyless, dark, and a close match for the app's
  /// near-black ground.
  static const dark = MapStyle(
    id: 'dark',
    label: 'Dark',
    urlTemplate:
        'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/'
        'World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}',
    maxZoom: 19,
    yBeforeX: true,
    attribution: 'Esri, HERE, Garmin, OpenStreetMap, USGS, OpenTopoMap, NPS, NGA',
    requiresKey: false,
    referenceUrlTemplate:
        'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/'
        'World_Dark_Gray_Reference/MapServer/tile/{z}/{y}/{x}',
  );

  /// OpenStreetMap standard tiles: the light fallback and last resort.
  static const street = MapStyle(
    id: 'street',
    label: 'Street',
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    maxZoom: 19,
    attribution: 'OpenStreetMap contributors',
    requiresKey: false,
  );

  /// md5 of the tile CARTO serves instead of a map when anonymous access is
  /// refused ("API KEY REQUIRED", 2513 bytes). Detected so the map can fall
  /// back rather than render a wall of that text.
  static const watermarkMd5 = 'df9307c738f2c6dbc0f8d31837019f98';

  /// CARTO dark tiles — only reachable once the user has saved a key.
  static MapStyle carto(String apiKey) => MapStyle(
    id: 'carto',
    label: 'CARTO dark',
    urlTemplate:
        'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
        '${apiKey.isEmpty ? '' : '?api_key=$apiKey'}',
    subdomains: const ['a', 'b', 'c', 'd'],
    maxZoom: 18,
    attribution: 'OpenStreetMap contributors, CARTO',
    requiresKey: true,
  );

  /// Every style the settings picker may offer for the stored key.
  static List<MapStyle> available({required String cartoApiKey}) => [
    dark,
    street,
    if (cartoApiKey.isNotEmpty) carto(cartoApiKey),
  ];

  /// Resolves a persisted id; unknown ids fall back to [dark] so a stale
  /// preference can never leave the map blank.
  static MapStyle byId(String id, {String cartoApiKey = ''}) {
    if (id == 'street') return street;
    if (id == 'carto' && cartoApiKey.isNotEmpty) return carto(cartoApiKey);
    return dark;
  }

  /// Builds a concrete tile URL for a probe or a debug fetch.
  static String tileUrl(MapStyle style, int z, int x, int y) {
    var url = style.urlTemplate;
    if (style.subdomains.isNotEmpty) {
      url = url.replaceFirst('{s}', style.subdomains.first);
    }
    url = url
        .replaceAll('{z}', '$z')
        .replaceAll('{x}', '$x')
        .replaceAll('{y}', '$y')
        .replaceAll('{r}', '');
    return url;
  }
}

/// Result of asking a basemap whether it will actually render a map.
enum TileProbeResult {
  /// Tiles are real map imagery.
  ok,

  /// The server answered with its "API key required" watermark.
  watermark,

  /// Unreachable, refused, or not an image at all.
  failed,
}

/// Fetches one known tile and classifies the answer. A watermark is a
/// successful HTTP response with map-breaking content, so status codes alone
/// cannot detect it — the body is checked against the known digest.
Future<TileProbeResult> probeTiles(
  MapStyle style, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final owned = client ?? http.Client();
  try {
    final uri = Uri.parse(TileSources.tileUrl(style, 0, 0, 0));
    final response = await owned
        .get(uri, headers: const {'User-Agent': 'com.photospot.app'})
        .timeout(timeout);

    if (response.statusCode != 200) return TileProbeResult.failed;

    var contentType = '';
    response.headers.forEach((key, value) {
      if (key.toLowerCase() == 'content-type') contentType = value;
    });
    if (!contentType.contains('image/')) return TileProbeResult.failed;

    final digest = md5.convert(response.bodyBytes).toString();
    if (digest == TileSources.watermarkMd5) return TileProbeResult.watermark;
    return TileProbeResult.ok;
  } catch (_) {
    return TileProbeResult.failed;
  } finally {
    if (client == null) owned.close();
  }
}

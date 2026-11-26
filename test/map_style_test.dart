import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:photospot/map/map_tile_layers.dart';
import 'package:photospot/map/tile_sources.dart';

/// Pumps [layers] inside a real map so the layer stack behaves the way it
/// does on device.
Future<void> _pumpMap(WidgetTester tester, Widget layers) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FlutterMap(
          options: MapOptions(initialCenter: LatLng(0, 0), initialZoom: 2),
          children: [layers],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('falls back to street when the probe reports the watermark', (
    tester,
  ) async {
    final fallbacks = <String>[];
    await _pumpMap(
      tester,
      MapTileLayers(
        style: TileSources.carto(''),
        onFallback: fallbacks.add,
        probe: (_) async => TileProbeResult.watermark,
      ),
    );
    await tester.pumpAndSettle();

    expect(fallbacks, ['street']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the active style when the probe reports ok', (
    tester,
  ) async {
    final fallbacks = <String>[];
    await _pumpMap(
      tester,
      MapTileLayers(
        style: TileSources.dark,
        onFallback: fallbacks.add,
        probe: (_) async => TileProbeResult.ok,
      ),
    );
    await tester.pumpAndSettle();

    expect(fallbacks, isEmpty);
    expect(find.byType(TileLayer), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('falls back when the probe fails outright', (tester) async {
    final fallbacks = <String>[];
    await _pumpMap(
      tester,
      MapTileLayers(
        style: TileSources.dark,
        onFallback: fallbacks.add,
        probe: (_) async => TileProbeResult.failed,
      ),
    );
    await tester.pumpAndSettle();

    expect(fallbacks, ['street']);
  });

  testWidgets('retry probes the tiles again', (tester) async {
    var calls = 0;
    await _pumpMap(
      tester,
      MapTileLayers(
        style: TileSources.street,
        onFallback: (_) {},
        probe: (_) async {
          calls++;
          return TileProbeResult.failed;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, 1);

    final state = tester.state<MapTileLayersState>(
      find.byType(MapTileLayers),
    );
    await state.retry();
    await tester.pumpAndSettle();

    expect(calls, 2);
  });

  testWidgets('the unavailable view offers a retry action', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapUnavailableView(
            styleLabel: 'Dark',
            onRetry: () => retried = true,
          ),
        ),
      ),
    );

    expect(find.text('Map tiles unavailable'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(retried, isTrue);
  });

  testWidgets('attribution renders for the active style', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: MapAttribution(style: TileSources.dark),
          ),
        ),
      ),
    );

    expect(find.byType(RichAttributionWidget), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

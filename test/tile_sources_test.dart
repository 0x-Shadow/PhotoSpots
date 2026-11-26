import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photospot/map/tile_sources.dart';
import 'package:photospot/state/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final watermarkBytes =
      File('test/fixtures/carto_watermark.png').readAsBytesSync();

  group('tileUrl', () {
    test('puts y before x for Esri styles', () {
      final url = TileSources.tileUrl(TileSources.dark, 13, 3888, 3139);
      expect(url, contains('/tile/13/3139/3888'));
    });

    test('keeps x before y for the street style', () {
      final url = TileSources.tileUrl(TileSources.street, 12, 2047, 1583);
      expect(url, contains('/12/2047/1583.png'));
      expect(url, isNot(contains('{')));
    });

    test('appends the CARTO api key when present', () {
      final withKey = TileSources.tileUrl(TileSources.carto('abc'), 12, 2047, 1583);
      expect(withKey, endsWith('1583.png?api_key=abc'));

      final withoutKey = TileSources.tileUrl(TileSources.carto(''), 12, 2047, 1583);
      expect(withoutKey, isNot(contains('api_key')));
      expect(withoutKey, endsWith('1583.png'));
    });
  });

  group('available styles', () {
    test('hides carto until a key is saved', () {
      expect(
        TileSources.available(cartoApiKey: '').map((s) => s.id),
        ['dark', 'street'],
      );
      expect(
        TileSources.available(cartoApiKey: 'abc').map((s) => s.id),
        ['dark', 'street', 'carto'],
      );
    });

    test('byId falls back to dark for an unknown id', () {
      expect(TileSources.byId('nope').id, 'dark');
      expect(TileSources.byId('carto', cartoApiKey: 'k').urlTemplate,
          contains('api_key=k'));
    });
  });

  group('probeTiles', () {
    test('returns failed when the request errors', () async {
      final client = MockClient((_) async {
        throw http.ClientException('boom');
      });
      expect(
        await probeTiles(TileSources.dark, client: client),
        TileProbeResult.failed,
      );
    });

    test('returns failed on a non-image body', () async {
      final client = MockClient(
        (_) async => http.Response(
          '<html>nope</html>',
          200,
          headers: {'content-type': 'text/html'},
        ),
      );
      expect(
        await probeTiles(TileSources.dark, client: client),
        TileProbeResult.failed,
      );
    });

    test('returns failed on a non-200 status', () async {
      final client = MockClient(
        (_) async => http.Response.bytes(
          watermarkBytes,
          503,
          headers: {'content-type': 'image/png'},
        ),
      );
      expect(
        await probeTiles(TileSources.carto(''), client: client),
        TileProbeResult.failed,
      );
    });

    test('classifies the known watermark digest as unavailable', () async {
      final client = MockClient(
        (_) async => http.Response.bytes(
          watermarkBytes,
          200,
          headers: {'content-type': 'image/png'},
        ),
      );
      expect(
        await probeTiles(TileSources.carto(''), client: client),
        TileProbeResult.watermark,
      );
    });

    test('returns ok for a normal png', () async {
      final client = MockClient(
        (_) async => http.Response.bytes(
          const [137, 80, 78, 71, 1, 2, 3],
          200,
          headers: {'content-type': 'image/png'},
        ),
      );
      expect(
        await probeTiles(TileSources.dark, client: client),
        TileProbeResult.ok,
      );
    });
  });

  group('SettingsState map style', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('persists the map style and the carto key', () async {
      final first = SettingsState();
      await first.setMapStyle('street');
      await first.setCartoApiKey('abc');

      final second = SettingsState();
      await second.load();
      expect(second.mapStyle, 'street');
      expect(second.cartoApiKey, 'abc');
      expect(second.activeMapStyle.id, 'street');
    });

    test('defaults to the dark style with no key', () async {
      final state = SettingsState();
      await state.load();
      expect(state.mapStyle, 'dark');
      expect(state.cartoApiKey, '');
      expect(state.activeMapStyle.id, 'dark');
      expect(state.activeMapStyle.requiresKey, isFalse);
    });
  });
}

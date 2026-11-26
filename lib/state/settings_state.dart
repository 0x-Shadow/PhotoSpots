import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../map/tile_sources.dart';

/// User preferences persisted locally. Small on purpose: every flag here is
/// consumed by at least one screen.
class SettingsState extends ChangeNotifier {
  SettingsState();

  /// Whether to check the release channel when the app opens.
  static const checkUpdatesKey = 'check_updates';
  static const metricUnitsKey = 'metric_units';
  static const mapPhotoPinsKey = 'map_photo_pins';
  static const mapStyleKey = 'map_style';
  static const cartoApiKeyKey = 'carto_api_key';

  bool _checkUpdates = true;
  bool _metricUnits = true;
  bool _mapPhotoPins = true;
  String _mapStyle = 'dark';
  String _cartoApiKey = '';
  bool _loaded = false;

  bool get checkUpdates => _checkUpdates;
  bool get metricUnits => _metricUnits;
  bool get mapPhotoPins => _mapPhotoPins;
  String get mapStyle => _mapStyle;
  String get cartoApiKey => _cartoApiKey;
  bool get loaded => _loaded;

  /// The basemap the map screens should render right now.
  MapStyle get activeMapStyle =>
      TileSources.byId(_mapStyle, cartoApiKey: _cartoApiKey);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _checkUpdates = prefs.getBool(checkUpdatesKey) ?? true;
      _metricUnits = prefs.getBool(metricUnitsKey) ?? true;
      _mapPhotoPins = prefs.getBool(mapPhotoPinsKey) ?? true;
      _mapStyle = prefs.getString(mapStyleKey) ?? 'dark';
      _cartoApiKey = prefs.getString(cartoApiKeyKey) ?? '';
    } catch (_) {
      // Keep defaults when storage is unavailable.
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setCheckUpdates(bool value) async {
    _checkUpdates = value;
    notifyListeners();
    await _write(checkUpdatesKey, value);
  }

  Future<void> setMetricUnits(bool value) async {
    _metricUnits = value;
    notifyListeners();
    await _write(metricUnitsKey, value);
  }

  Future<void> setMapPhotoPins(bool value) async {
    _mapPhotoPins = value;
    notifyListeners();
    await _write(mapPhotoPinsKey, value);
  }

  /// Switches basemap style. Refuses a key-gated style while no key is saved
  /// so the map can never be pointed at tiles that will not render.
  Future<void> setMapStyle(String value) async {
    if (value == 'carto' && _cartoApiKey.isEmpty) return;
    _mapStyle = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(mapStyleKey, value);
    } catch (_) {
      // Preferences are non-critical; the in-memory value still applies.
    }
  }

  Future<void> setCartoApiKey(String value) async {
    _cartoApiKey = value.trim();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cartoApiKeyKey, _cartoApiKey);
    } catch (_) {
      // Preferences are non-critical; the in-memory value still applies.
    }
  }

  Future<void> _write(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {
      // Preferences are non-critical; the in-memory value still applies.
    }
  }
}

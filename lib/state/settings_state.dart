import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User preferences persisted locally. Small on purpose: every flag here is
/// consumed by at least one screen.
class SettingsState extends ChangeNotifier {
  SettingsState();

  /// Whether to check the release channel when the app opens.
  static const checkUpdatesKey = 'check_updates';
  static const metricUnitsKey = 'metric_units';
  static const mapPhotoPinsKey = 'map_photo_pins';

  bool _checkUpdates = true;
  bool _metricUnits = true;
  bool _mapPhotoPins = true;
  bool _loaded = false;

  bool get checkUpdates => _checkUpdates;
  bool get metricUnits => _metricUnits;
  bool get mapPhotoPins => _mapPhotoPins;
  bool get loaded => _loaded;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _checkUpdates = prefs.getBool(checkUpdatesKey) ?? true;
      _metricUnits = prefs.getBool(metricUnitsKey) ?? true;
      _mapPhotoPins = prefs.getBool(mapPhotoPinsKey) ?? true;
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

  Future<void> _write(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {
      // Preferences are non-critical; the in-memory value still applies.
    }
  }
}

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/spot_repository.dart';
import '../models/spot.dart';
import 'location_outcome.dart';

/// Central app state: spots, saves, ranking, submission, and location.
class AppState extends ChangeNotifier {
  AppState(this._repo);

  static const savedIdsKey = 'saved_spot_ids';
  static const lastLatKey = 'last_lat';
  static const lastLngKey = 'last_lng';
  static const lastFixAtKey = 'last_fix_at';

  /// Lisbon — where the seed data lives. Used as the reference point until a
  /// real location fix arrives.
  static const fallbackCenter = LatLng(38.7128, -9.1393);

  final SpotRepository _repo;

  SpotRepository get repository => _repo;

  List<Spot> _spots = [];
  final Set<String> _savedIds = {};
  final Set<String> _viewedIds = {};

  bool _loading = true;
  Object? _error;
  Position? _userLocation;
  LatLng? _cachedFix;
  bool _locationLoading = false;
  LocationOutcome? _lastOutcome;
  bool _disposed = false;

  bool get loading => _loading;
  Object? get error => _error;
  List<Spot> get spots => List.unmodifiable(_spots);
  Set<String> get savedIds => Set.unmodifiable(_savedIds);
  Position? get userLocation => _userLocation;
  bool get hasUserLocation => _userLocation != null;
  bool get locationLoading => _locationLoading;

  /// The most recent result of [requestLocation], for UIs that need to show
  /// a recovery action.
  LocationOutcome? get lastLocationOutcome => _lastOutcome;

  /// True once a fix — live or from a previous launch — is known.
  bool get hasCachedFix => _cachedFix != null;

  /// True when distances can be measured from a real position rather than the
  /// demo seed.
  bool get hasReferenceFix => _userLocation != null || _cachedFix != null;

  /// Spots opened this session, used for the profile "Visited" stat.
  int get viewedCount => _viewedIds.length;

  /// Where distance labels are measured from: a live fix, then the fix from
  /// an earlier launch, and only then the demo city.
  LatLng get referenceLocation => _userLocation != null
      ? LatLng(_userLocation!.latitude, _userLocation!.longitude)
      : (_cachedFix ?? fallbackCenter);

  List<Spot> get savedSpots =>
      _spots.where((spot) => _savedIds.contains(spot.id)).toList();

  /// Spots ordered by algorithmic rank (best first).
  List<Spot> get rankedSpots =>
      [..._spots]..sort((a, b) => b.score.compareTo(a.score));

  /// Spots within [radiusKm] of [origin], nearest first.
  List<Spot> nearby(LatLng origin, {double radiusKm = 25}) {
    const distance = Distance();
    final list = _spots.where((spot) {
      final km = distance.as(LengthUnit.Kilometer, origin, spot.location);
      return km <= radiusKm;
    }).toList();
    list.sort((a, b) => distance
        .as(LengthUnit.Kilometer, origin, a.location)
        .compareTo(distance.as(LengthUnit.Kilometer, origin, b.location)));
    return list;
  }

  bool isSaved(String spotId) => _savedIds.contains(spotId);

  Spot? spotById(String id) {
    for (final spot in _spots) {
      if (spot.id == id) return spot;
    }
    return null;
  }

  double distanceKm(LatLng origin, Spot spot) {
    const distance = Distance();
    return distance.as(LengthUnit.Kilometer, origin, spot.location);
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    _notify();

    try {
      final spots = await _repo.fetchSpots();
      final local = await _readSavedIds();
      await _readCachedFix();

      Set<String>? remote;
      try {
        remote = await _repo.fetchSavedIds();
      } catch (_) {
        // Saved ids are best effort; local state still works.
        remote = null;
      }

      _spots = List<Spot>.of(spots);
      // Keep saves made on this device even when the remote session is new or
      // empty; otherwise enabling sync would silently discard local saves.
      _savedIds
        ..clear()
        ..addAll(local)
        ..addAll(remote ?? const <String>{});
      await _persistSavedIds();
      _error = null;
    } catch (error) {
      _error = error;
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Re-fetches spots after a transient failure.
  Future<void> refresh() async {
    try {
      _spots = List<Spot>.of(await _repo.fetchSpots());
      _error = null;
    } catch (error) {
      _error = error;
    }
    _notify();
  }

  /// Toggles the bookmark. Returns false when the change could not be synced
  /// (the save is still kept locally).
  Future<bool> toggleSave(Spot spot) async {
    final wasSaved = _savedIds.contains(spot.id);
    final next = !wasSaved;

    if (next) {
      _savedIds.add(spot.id);
    } else {
      _savedIds.remove(spot.id);
    }
    _notify();
    await _persistSavedIds();

    try {
      final synced = await _repo.toggleSave(spot, saved: next);
      if (!synced) return false;

      try {
        _spots = List<Spot>.of(await _repo.fetchSpots());
      } catch (_) {
        // Keep the optimistic list; the save itself succeeded.
      }
      _notify();
      return true;
    } catch (_) {
      if (wasSaved) {
        _savedIds.add(spot.id);
      } else {
        _savedIds.remove(spot.id);
      }
      await _persistSavedIds();
      _notify();
      return false;
    }
  }

  Future<void> recordView(Spot spot) async {
    // One view per spot per app session keeps ranking honest.
    if (!_viewedIds.add(spot.id)) return;

    final index = _spots.indexWhere((s) => s.id == spot.id);
    if (index != -1) {
      _spots[index] =
          _spots[index].copyWith(viewCount: _spots[index].viewCount + 1);
      _notify();
    }

    try {
      await _repo.recordView(spot);
    } catch (_) {
      // View tracking is analytics-only; never surface it.
    }
  }

  Future<Spot> submitSpot({
    required String title,
    required String description,
    required LatLng location,
    required String city,
    required List<String> tags,
    String? bestTime,
    Uint8List? photoBytes,
  }) async {
    final spot = await _repo.submitSpot(
      title: title,
      description: description,
      location: location,
      city: city,
      tags: tags,
      bestTime: bestTime,
      photoBytes: photoBytes,
    );

    try {
      _spots = List<Spot>.of(await _repo.fetchSpots());
    } catch (_) {
      _spots = [spot, ..._spots];
    }
    _notify();
    return spot;
  }

  /// Requests a location fix and reports exactly what happened, so callers
  /// can offer the right recovery action instead of a dead-end message.
  Future<LocationOutcome> requestLocation() async {
    if (_locationLoading) return _lastOutcome ?? LocationOutcome.failed;

    _locationLoading = true;
    _notify();

    try {
      final servicesEnabled = await Geolocator.isLocationServiceEnabled();
      if (!servicesEnabled) {
        return _lastOutcome = LocationOutcome.servicesOff;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      final outcome = classifyLocation(
        servicesEnabled: servicesEnabled,
        deniedForever: permission == LocationPermission.deniedForever,
        denied: permission == LocationPermission.denied,
      );
      if (outcome != LocationOutcome.granted) {
        return _lastOutcome = outcome;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      _userLocation = position;
      await cacheFix(position.latitude, position.longitude);
      return _lastOutcome = LocationOutcome.granted;
    } catch (_) {
      return _lastOutcome = LocationOutcome.failed;
    } finally {
      _locationLoading = false;
      _notify();
    }
  }

  /// Remembers an outcome reported by a caller (e.g. Settings) so every screen
  /// reads the same status.
  void recordLocationOutcome(LocationOutcome outcome) {
    _lastOutcome = outcome;
    _notify();
  }

  /// Called when the app returns from the background. If the user granted
  /// permission in system settings, pick up the fix without asking again.
  void onAppResumed() {
    if (_locationLoading || hasUserLocation) return;
    Geolocator.checkPermission().then((permission) {
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        requestLocation();
      }
    }).catchError((_) {
      // A failed recheck is invisible; the user can still tap the location
      // button, which runs the full recovery flow.
    });
  }

  /// Remembers the last good fix so the next launch can sort distances from
  /// the user's own city instead of the demo seed.
  Future<void> cacheFix(double lat, double lng) async {
    _cachedFix = LatLng(lat, lng);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(lastLatKey, lat);
      await prefs.setDouble(lastLngKey, lng);
      await prefs.setDouble(
        lastFixAtKey,
        DateTime.now().millisecondsSinceEpoch.toDouble(),
      );
    } catch (_) {
      // Local persistence is best effort.
    }
    _notify();
  }

  /// Adopts a fresh live fix as both the current position and the cached one.
  Future<void> adoptLiveFix(double lat, double lng) async {
    await cacheFix(lat, lng);
  }

  Future<void> _readCachedFix() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble(lastLatKey);
      final lng = prefs.getDouble(lastLngKey);
      if (lat != null && lng != null) _cachedFix = LatLng(lat, lng);
    } catch (_) {
      // No cache is the normal first-run state.
    }
  }

  Future<Set<String>> _readSavedIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(savedIdsKey) ?? const []).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> _persistSavedIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(savedIdsKey, _savedIds.toList());
    } catch (_) {
      // Local persistence is best effort.
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

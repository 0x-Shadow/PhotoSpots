import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../data/supabase_repository.dart';
import '../data/spot_repository.dart';
import '../models/spot.dart';

/// Central app state: spots, saves, ranking, submission, location, updates.
class AppState extends ChangeNotifier {
  final SpotRepository _repo;
  SpotRepository get repository => _repo;

  AppState(this._repo);

  List<Spot> _spots = [];
  final Set<String> _savedIds = {};
  bool _loading = true;
  Position? _userLocation;
  bool _locationLoading = false;
  String? _updateMessage;
  VersionInfo? _latestVersion;

  bool get loading => _loading;
  List<Spot> get spots => List.unmodifiable(_spots);
  Set<String> get savedIds => Set.unmodifiable(_savedIds);
  Position? get userLocation => _userLocation;
  bool get locationLoading => _locationLoading;
  String? get updateMessage => _updateMessage;
  VersionInfo? get latestVersion => _latestVersion;

  List<Spot> get savedSpots =>
      _spots.where((s) => _savedIds.contains(s.id)).toList();

  /// Spots ordered by algorithmic rank (best first).
  List<Spot> get rankedSpots {
    final list = [..._spots]..sort((a, b) => b.score.compareTo(a.score));
    return list;
  }

  /// Top N for the "Top spots" carousel.
  List<Spot> topSpots({int limit = 8}) => rankedSpots.take(limit).toList();

  /// Spots within [radiusKm] of [origin], nearest first.
  List<Spot> nearby(LatLng origin, {double radiusKm = 25}) {
    const dist = Distance();
    final list = _spots.where((s) {
      final meters = dist.as(LengthUnit.Kilometer, origin, s.location);
      return meters <= radiusKm;
    }).toList();
    list.sort((a, b) => dist.as(LengthUnit.Kilometer, origin, a.location)
        .compareTo(dist.as(LengthUnit.Kilometer, origin, b.location)));
    return list;
  }

  bool isSaved(String spotId) => _savedIds.contains(spotId);

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    _spots = await _repo.fetchSpots();
    _loading = false;
    notifyListeners();
    _checkForUpdates();
  }

  Future<void> _checkForUpdates() async {
    try {
      // Lightweight check — GitHub releases API, no auth needed
      final response = await http.get(
        Uri.parse(
            'https://api.github.com/repos/0x-Shadow/PhotoSpots/releases/latest'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final tagName = data['tag_name'] as String? ?? '';
        final body = data['body'] as String? ?? 'New version available';
        final downloadUrl = data['html_url'] as String? ?? '';

        // Compare with current version (1.0.0)
        final current = VersionInfo(1, 0, 0);
        final latest = _parseVersion(tagName);
        if (latest != null && latest.isNewerThan(current)) {
          _updateMessage = body;
          _latestVersion = latest;
          notifyListeners();
        }
      }
    } catch (_) {
      // Silent fail — update check is non-critical
    }
  }

  VersionInfo _parseVersion(String tag) {
    // Strip leading 'v' if present
    final clean = tag.startsWith('v') ? tag.substring(1) : tag;
    final parts = clean.split('.');
    if (parts.length >= 3) {
      return VersionInfo(
        int.tryParse(parts[0]) ?? 0,
        int.tryParse(parts[1]) ?? 0,
        int.tryParse(parts[2]) ?? 0,
      );
    }
    return VersionInfo(0, 0, 0);
  }

  Future<void> requestLocation() async {
    _locationLoading = true;
    notifyListeners();

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _locationLoading = false;
      notifyListeners();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _userLocation = position;
    }

    _locationLoading = false;
    notifyListeners();
  }

  Future<void> toggleSave(Spot spot) async {
    final wasSaved = _savedIds.contains(spot.id);
    if (wasSaved) {
      _savedIds.remove(spot.id);
    } else {
      _savedIds.add(spot.id);
    }
    notifyListeners();
    try {
      await _repo.toggleSave(spot, saved: !wasSaved);
      _spots = await _repo.fetchSpots();
      notifyListeners();
    } catch (_) {
      if (wasSaved) {
        _savedIds.add(spot.id);
      } else {
        _savedIds.remove(spot.id);
      }
      notifyListeners();
    }
  }

  Future<void> recordView(Spot spot) async {
    final i = _spots.indexWhere((s) => s.id == spot.id);
    if (i != -1) {
      _spots[i] = _spots[i].copyWith(viewCount: _spots[i].viewCount + 1);
      notifyListeners();
    }
    await _repo.recordView(spot);
  }

  Future<Spot> submitSpot({
    required String title,
    required String description,
    required LatLng location,
    required String city,
    required List<String> tags,
    String? bestTime,
    String? photoUrl,
  }) async {
    final spot = await _repo.submitSpot(
      title: title,
      description: description,
      location: location,
      city: city,
      tags: tags,
      bestTime: bestTime,
      photoUrl: photoUrl,
    );
    _spots = await _repo.fetchSpots();
    notifyListeners();
    return spot;
  }

  double distanceKm(LatLng origin, Spot spot) {
    const dist = Distance();
    return dist.as(LengthUnit.Kilometer, origin, spot.location);
  }
}

/// Version info for update checking.
class VersionInfo {
  final int major;
  final int minor;
  final int patch;

  VersionInfo(this.major, this.minor, this.patch);

  bool isNewerThan(VersionInfo other) {
    if (major != other.major) return major > other.major;
    if (minor != other.minor) return minor > other.minor;
    return patch > other.patch;
  }

  String toString() => '$major.$minor.$patch';
}

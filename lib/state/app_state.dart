import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/spot_repository.dart';
import '../models/comment.dart';
import '../models/spot.dart';
import '../utils/categories.dart';
import '../utils/ranking.dart';
import 'location_outcome.dart';

/// Central app state: spots, saves, ranking, submission, and location.
class AppState extends ChangeNotifier {
  AppState(this._repo);

  static const savedIdsKey = 'saved_spot_ids';
  static const likedIdsKey = 'liked_spot_ids';
  static const viewedIdsKey = 'viewed_spot_ids';
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
  final Set<String> _likedIds = {};
  final Set<String> _viewedIds = {};
  final Map<String, List<SpotComment>> _comments = {};
  final Set<String> _loadingComments = {};

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

  /// Spots opened on this device, used for the profile "Viewed" stat and as
  /// the weakest taste signal.
  int get viewedCount => _viewedIds.length;

  int get likedCount => _likedIds.length;

  /// Where distance labels are measured from: a live fix, then the fix from
  /// an earlier launch, and only then the demo city.
  LatLng get referenceLocation => _userLocation != null
      ? LatLng(_userLocation!.latitude, _userLocation!.longitude)
      : (_cachedFix ?? fallbackCenter);

  List<Spot> get savedSpots =>
      _spots.where((spot) => _savedIds.contains(spot.id)).toList();

  List<Spot> get likedSpots =>
      _spots.where((spot) => _likedIds.contains(spot.id)).toList();

  List<Spot> get submittedSpots =>
      _spots.where((spot) => spot.submittedBy == 'you').toList();

  /// Spots ordered by algorithmic rank (best first).
  List<Spot> get rankedSpots =>
      [..._spots]..sort((a, b) => b.score.compareTo(a.score));

  /// Spots ordered by raw community engagement, for "most famous" surfaces.
  List<Spot> get mostEngaged =>
      [..._spots]..sort((a, b) => b.engagementCount.compareTo(a.engagementCount));

  /// What this person's saves, likes, views and uploads say they care about.
  InterestProfile get interestProfile => InterestProfile.fromActivity(
        saved: savedSpots,
        liked: likedSpots,
        viewed: _spots.where((spot) => _viewedIds.contains(spot.id)),
        published: submittedSpots,
      );

  bool get hasTasteProfile => !interestProfile.isEmpty;

  /// Strongest interest tags, used to explain recommendations.
  List<String> get topInterests => interestProfile.topTags(limit: 8);

  /// Categories arranged by how much of this person's activity they cover.
  List<SpotCategory> get affinityCategories {
    final counts = <String, int>{};
    for (final spot in _spots) {
      final weight = (_savedIds.contains(spot.id) ? InterestProfile.saveWeight : 0) +
          (_likedIds.contains(spot.id) ? InterestProfile.likeWeight : 0) +
          (_viewedIds.contains(spot.id) ? InterestProfile.viewWeight : 0) +
          (spot.submittedBy == 'you' ? InterestProfile.publishWeight : 0);
      if (weight == 0) continue;
      for (final category in categoriesForSpot(spot)) {
        counts[category.id] = (counts[category.id] ?? 0) + weight;
      }
    }
    final ranked = spotCategories.where((c) => counts.containsKey(c.id)).toList()
      ..sort((a, b) => counts[b.id]!.compareTo(counts[a.id]!));
    return ranked;
  }

  /// Personalised feed: community popularity blended with learned taste.
  List<Spot> get recommendedSpots =>
      SpotRanking.recommend(_spots, interestProfile);

  /// Spots in [category], ranked by popularity first and taste second.
  List<Spot> categorySpots(SpotCategory category) =>
      SpotRanking.recommend(spotsInCategory(_spots, category), interestProfile);

  bool isLiked(String spotId) => _likedIds.contains(spotId);

  List<SpotComment> commentsFor(String spotId) =>
      List.unmodifiable(_comments[spotId] ?? const <SpotComment>[]);

  bool isLoadingComments(String spotId) => _loadingComments.contains(spotId);

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
      final local = await _readIds(savedIdsKey);
      await _readCachedFix();

      Set<String>? remote;
      try {
        remote = await _repo.fetchSavedIds();
      } catch (_) {
        // Saved ids are best effort; local state still works.
        remote = null;
      }

      final likedLocal = await _readIds(likedIdsKey);
      final viewed = await _readIds(viewedIdsKey);

      Set<String>? remoteLikes;
      try {
        remoteLikes = await _repo.fetchLikedIds();
      } catch (_) {
        remoteLikes = null;
      }

      _spots = List<Spot>.of(spots);
      // Keep saves and likes made on this device even when the remote session
      // is new or empty; otherwise enabling sync would silently discard them.
      _savedIds
        ..clear()
        ..addAll(local)
        ..addAll(remote ?? const <String>{});
      _likedIds
        ..clear()
        ..addAll(likedLocal)
        ..addAll(remoteLikes ?? const <String>{});
      _viewedIds
        ..clear()
        ..addAll(viewed);
      await _persistIds(savedIdsKey, _savedIds);
      await _persistIds(likedIdsKey, _likedIds);
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
    await _persistIds(savedIdsKey, _savedIds);

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
      await _persistIds(savedIdsKey, _savedIds);
      _notify();
      return false;
    }
  }

  /// Toggles a like. Returns false when the like could not be synced (it is
  /// still kept locally so the UI never lies about the tap).
  Future<bool> toggleLike(Spot spot) async {
    final wasLiked = _likedIds.contains(spot.id);
    final next = !wasLiked;

    if (next) {
      _likedIds.add(spot.id);
    } else {
      _likedIds.remove(spot.id);
    }
    _applyLikeCount(spot.id, next ? 1 : -1);
    _notify();
    await _persistIds(likedIdsKey, _likedIds);

    try {
      final synced = await _repo.toggleLike(spot, liked: next);
      if (!synced) return false;

      try {
        _spots = List<Spot>.of(await _repo.fetchSpots());
        _notify();
      } catch (_) {
        // The local count already reflects the tap.
      }
      return true;
    } catch (_) {
      if (wasLiked) {
        _likedIds.add(spot.id);
      } else {
        _likedIds.remove(spot.id);
      }
      _applyLikeCount(spot.id, wasLiked ? 1 : -1);
      _notify();
      await _persistIds(likedIdsKey, _likedIds);
      return false;
    }
  }

  void _applyLikeCount(String spotId, int delta) {
    final index = _spots.indexWhere((s) => s.id == spotId);
    if (index == -1) return;
    final next = _spots[index].likeCount + delta;
    _spots[index] = _spots[index].copyWith(likeCount: next < 0 ? 0 : next);
  }

  Future<void> recordView(Spot spot) async {
    // One counted view per spot per device keeps ranking honest.
    final firstView = _viewedIds.add(spot.id);
    if (firstView) {
      await _persistIds(viewedIdsKey, _viewedIds);
      _notify();
    }
    final index = _spots.indexWhere((s) => s.id == spot.id);
    if (index != -1 && firstView) {
      _spots[index] =
          _spots[index].copyWith(viewCount: _spots[index].viewCount + 1);
    }

    if (!firstView) return;
    try {
      await _repo.recordView(spot);
    } catch (_) {
      // View tracking is analytics-only; never surface it.
    }
  }

  /// Forgets which spots were viewed, which is the only implicit signal in
  /// the taste profile. Saves and likes are explicit and stay.
  Future<void> clearViewHistory() async {
    _viewedIds.clear();
    await _persistIds(viewedIdsKey, _viewedIds);
    _notify();
  }

  /// Loads the comment thread once per spot and keeps it cached.
  Future<void> loadComments(String spotId, {bool force = false}) async {
    if (_loadingComments.contains(spotId)) return;
    if (!force && _comments.containsKey(spotId)) return;

    _loadingComments.add(spotId);
    _notify();
    try {
      final comments = await _repo.fetchComments(spotId);
      _comments[spotId] = comments;
      final index = _spots.indexWhere((s) => s.id == spotId);
      if (index != -1) {
        _spots[index] = _spots[index].copyWith(
          commentCount: comments.length,
        );
      }
    } catch (_) {
      // Leave the cached list (possibly empty) in place; posting still works.
    } finally {
      _loadingComments.remove(spotId);
      _notify();
    }
  }

  /// Posts a comment, optimistically inserting it so the thread feels instant.
  /// Throws [AppException] with a user-safe message when it fails.
  Future<SpotComment> postComment(String spotId, String body) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      throw const AppException('Write something first.');
    }
    if (trimmed.length > 500) {
      throw const AppException('Keep comments under 500 characters.');
    }

    final comment = await _repo.addComment(spotId: spotId, body: trimmed);
    _comments[spotId] = [comment, ...?_comments[spotId]];
    final index = _spots.indexWhere((s) => s.id == spotId);
    if (index != -1) {
      _spots[index] = _spots[index].copyWith(
        commentCount: _spots[index].commentCount + 1,
      );
    }
    _notify();
    return comment;
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

  Future<Set<String>> _readIds(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(key) ?? const []).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> _persistIds(String key, Set<String> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(key, ids.toList());
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

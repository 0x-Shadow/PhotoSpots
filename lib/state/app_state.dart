import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_info.dart';
import '../data/spot_repository.dart';
import '../models/comment.dart';
import '../models/spot.dart';
import '../utils/categories.dart';
import '../utils/ranking.dart';
import 'location_outcome.dart';

/// Central app state: spots, saves, ranking, submission, moderation, and location.
class AppState extends ChangeNotifier {
  AppState(this._repo);

  static const savedIdsKey = 'saved_spot_ids';
  static const savedSpotsCacheKey = 'saved_spots_cache_v1';
  static const likedIdsKey = 'liked_spot_ids';
  static const viewedIdsKey = 'viewed_spot_ids';
  static const blockedUserIdsKey = 'blocked_user_ids';
  static const hiddenSpotIdsKey = 'hidden_spot_ids';
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
  final Set<String> _blockedUserIds = {};
  final Set<String> _hiddenSpotIds = {};
  final Map<String, List<SpotComment>> _comments = {};
  final Set<String> _loadingComments = {};

  /// Per-spot serialization queue so rapid taps on save/like never race or
  /// apply out-of-order responses.
  final Map<String, Future<void>> _spotQueues = {};

  /// Monotonic version to prevent stale load()/refresh() calls from
  /// overwriting newer state.
  int _loadSeq = 0;

  String? _activeUserId = AppInfo.backendConfigured ? null : 'you';
  bool _personalizeFeed = true;

  bool _loading = true;
  Object? _error;
  Position? _userLocation;
  LatLng? _cachedFix;
  bool _locationLoading = false;
  LocationOutcome? _lastOutcome;
  bool _disposed = false;

  bool get loading => _loading;
  Object? get error => _error;
  List<Spot> get spots => List.unmodifiable(
        _spots.where((s) =>
            !_hiddenSpotIds.contains(s.id) &&
            (s.submittedById == null ||
                !_blockedUserIds.contains(s.submittedById))),
      );
  Set<String> get savedIds => Set.unmodifiable(_savedIds);
  Set<String> get blockedUserIds => Set.unmodifiable(_blockedUserIds);
  Position? get userLocation => _userLocation;
  bool get hasUserLocation => _userLocation != null;
  bool get locationLoading => _locationLoading;
  String? get activeUserId => _activeUserId;
  bool get personalizeFeed => _personalizeFeed;

  /// Keeps user identity & personalization preference synchronized from
  /// [AuthState] and [SettingsState].
  void syncContext({
    required String? activeUserId,
    required bool personalizeFeed,
  }) {
    final userChanged = _activeUserId != activeUserId;
    final prefChanged = _personalizeFeed != personalizeFeed;
    _activeUserId = activeUserId;
    _personalizeFeed = personalizeFeed;
    if (userChanged && AppInfo.backendConfigured) {
      // Refresh remote saves/likes/blocks when account changes.
      refreshUserSignals();
    } else if (userChanged || prefChanged) {
      _notify();
    }
  }

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
      spots.where((spot) => _savedIds.contains(spot.id)).toList();

  List<Spot> get likedSpots =>
      spots.where((spot) => _likedIds.contains(spot.id)).toList();

  List<Spot> get submittedSpots {
    final uid = _activeUserId;
    if (uid == null || uid.isEmpty) return const [];
    return spots
        .where((spot) =>
            spot.submittedById == uid ||
            (!AppInfo.backendConfigured && spot.submittedBy == 'you'))
        .toList();
  }

  /// Spots ordered by algorithmic rank (best first) using one frozen clock.
  List<Spot> get rankedSpots {
    final now = DateTime.now();
    return [...spots]..sort((a, b) => b.scoreAt(now).compareTo(a.scoreAt(now)));
  }

  /// Spots ordered by raw community engagement, for "most famous" surfaces.
  List<Spot> get mostEngaged =>
      [...spots]..sort((a, b) => b.engagementCount.compareTo(a.engagementCount));

  /// What this person's saves, likes, views and uploads say they care about.
  InterestProfile get interestProfile {
    if (!_personalizeFeed) return InterestProfile.empty;
    return InterestProfile.fromActivity(
      saved: savedSpots,
      liked: likedSpots,
      viewed: spots.where((spot) => _viewedIds.contains(spot.id)),
      published: submittedSpots,
    );
  }

  bool get hasTasteProfile => !interestProfile.isEmpty;

  /// Strongest interest tags, used to explain recommendations.
  List<String> get topInterests => interestProfile.topTags(limit: 8);

  /// Categories arranged by how much of this person's activity they cover.
  List<SpotCategory> get affinityCategories {
    final counts = <String, int>{};
    final uid = _activeUserId;
    for (final spot in spots) {
      final isOwn = uid != null &&
          (spot.submittedById == uid ||
              (!AppInfo.backendConfigured && spot.submittedBy == 'you'));
      final weight = (_savedIds.contains(spot.id) ? InterestProfile.saveWeight : 0) +
          (_likedIds.contains(spot.id) ? InterestProfile.likeWeight : 0) +
          (_viewedIds.contains(spot.id) ? InterestProfile.viewWeight : 0) +
          (isOwn ? InterestProfile.publishWeight : 0);
      if (weight == 0) continue;
      for (final category in categoriesForSpot(spot)) {
        counts[category.id] = (counts[category.id] ?? 0) + weight;
      }
    }
    final ranked = spotCategories.where((c) => counts.containsKey(c.id)).toList()
      ..sort((a, b) => counts[b.id]!.compareTo(counts[a.id]!));
    return ranked;
  }

  /// Personalised feed: community popularity blended with learned taste,
  /// current shooting light, and nearby proximity.
  List<Spot> get recommendedSpots => SpotRanking.recommend(
        spots,
        interestProfile,
        userLocation: hasReferenceFix ? referenceLocation : null,
      );

  /// Spots in [category], ranked by popularity first and taste second.
  List<Spot> categorySpots(SpotCategory category) => SpotRanking.recommend(
        spotsInCategory(spots, category),
        interestProfile,
        userLocation: hasReferenceFix ? referenceLocation : null,
      );

  bool isLiked(String spotId) => _likedIds.contains(spotId);

  List<SpotComment> commentsFor(String spotId) => List.unmodifiable(
        (_comments[spotId] ?? const <SpotComment>[]).where(
          (c) => !_blockedUserIds.contains(c.authorId),
        ),
      );

  bool isLoadingComments(String spotId) => _loadingComments.contains(spotId);

  /// Spots within [radiusKm] of [origin], nearest first.
  List<Spot> nearby(LatLng origin, {double radiusKm = 25}) {
    const distance = Distance();
    final list = spots.where((spot) {
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
    for (final spot in spots) {
      if (spot.id == id) return spot;
    }
    return null;
  }

  /// All visible spots published by a specific author id or display name.
  List<Spot> spotsByAuthor({String? authorId, String? authorName}) {
    return spots.where((spot) {
      if (authorId != null && authorId.isNotEmpty) {
        return spot.submittedById == authorId;
      }
      if (authorName != null && authorName.isNotEmpty) {
        return spot.submittedBy == authorName;
      }
      return false;
    }).toList();
  }

  double distanceKm(LatLng origin, Spot spot) {
    const distance = Distance();
    return distance.as(LengthUnit.Kilometer, origin, spot.location);
  }

  Future<void> load() async {
    final seq = ++_loadSeq;
    _loading = true;
    _error = null;
    _notify();

    try {
      final spots = await _repo.fetchSpots();
      final local = await _readIds(savedIdsKey);
      final likedLocal = await _readIds(likedIdsKey);
      final viewed = await _readIds(viewedIdsKey);
      final blockedLocal = await _readIds(blockedUserIdsKey);
      final hiddenLocal = await _readIds(hiddenSpotIdsKey);
      await _readCachedFix();

      Set<String>? remote;
      try {
        remote = await _repo.fetchSavedIds();
      } catch (_) {
        remote = null;
      }

      Set<String>? remoteLikes;
      try {
        remoteLikes = await _repo.fetchLikedIds();
      } catch (_) {
        remoteLikes = null;
      }

      Set<String>? remoteBlocked;
      try {
        remoteBlocked = await _repo.fetchBlockedUserIds();
      } catch (_) {
        remoteBlocked = null;
      }

      if (seq != _loadSeq) return;

      _spots = List<Spot>.of(spots);
      // Merge with any in-flight optimistic toggles so load() never clobbers
      // a tap that happened while loading was in progress.
      _savedIds
        ..addAll(local)
        ..addAll(remote ?? const <String>{});
      _likedIds
        ..addAll(likedLocal)
        ..addAll(remoteLikes ?? const <String>{});
      _viewedIds.addAll(viewed);
      _blockedUserIds
        ..addAll(blockedLocal)
        ..addAll(remoteBlocked ?? const <String>{});
      _hiddenSpotIds.addAll(hiddenLocal);

      await _persistIds(savedIdsKey, _savedIds);
      await _persistIds(likedIdsKey, _likedIds);
      await _persistIds(blockedUserIdsKey, _blockedUserIds);
      await _persistSavedSpotsCache();
      _error = null;
    } catch (error) {
      if (seq != _loadSeq) return;
      // If offline, restore cached saved spots so the Saved tab & Trip Planner
      // remain usable on the trail.
      final cachedSaved = await _readSavedSpotsCache();
      if (cachedSaved.isNotEmpty) {
        _spots = cachedSaved;
        _savedIds.addAll(await _readIds(savedIdsKey));
        _error = null;
      } else {
        _error = error;
      }
    } finally {
      if (seq == _loadSeq) {
        _loading = false;
        _notify();
      }
    }
  }

  /// Syncs remote user-owned lists (saves, likes, blocks) after signing in.
  Future<void> refreshUserSignals() async {
    try {
      final results = await Future.wait([
        _repo.fetchSavedIds().catchError((_) => null),
        _repo.fetchLikedIds().catchError((_) => null),
        _repo.fetchBlockedUserIds().catchError((_) => null),
      ]);
      final remoteSaves = results[0];
      final remoteLikes = results[1];
      final remoteBlocked = results[2];
      if (remoteSaves != null) _savedIds.addAll(remoteSaves);
      if (remoteLikes != null) _likedIds.addAll(remoteLikes);
      if (remoteBlocked != null) _blockedUserIds.addAll(remoteBlocked);
      _notify();
    } catch (_) {
      // Best-effort sync.
    }
  }

  /// Re-fetches spots after a transient failure.
  Future<void> refresh() async {
    final seq = ++_loadSeq;
    try {
      final next = await _repo.fetchSpots();
      if (seq != _loadSeq) return;
      _spots = List<Spot>.of(next);
      _error = null;
    } catch (error) {
      if (seq != _loadSeq) return;
      _error = error;
    }
    _notify();
  }

  Future<T> _serializeForSpot<T>(String spotId, Future<T> Function() action) {
    final prev = _spotQueues[spotId] ?? Future<void>.value();
    final completer = Completer<T>();
    final next = prev.catchError((_) {}).then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    _spotQueues[spotId] = next.whenComplete(() {
      if (identical(_spotQueues[spotId], next)) {
        _spotQueues.remove(spotId);
      }
    });
    return completer.future;
  }

  Future<void> _refreshSingleSpot(String spotId) async {
    final updated = await _repo.fetchSpot(spotId);
    if (updated == null) return;
    final idx = _spots.indexWhere((s) => s.id == spotId);
    if (idx != -1) {
      _spots[idx] = updated;
    }
  }

  /// Toggles the bookmark. Serialized per spot to eliminate race conditions and
  /// avoids re-fetching the entire table on every tap.
  Future<bool> toggleSave(Spot spot) {
    return _serializeForSpot(spot.id, () async {
      final wasSaved = _savedIds.contains(spot.id);
      final next = !wasSaved;

      if (next) {
        _savedIds.add(spot.id);
      } else {
        _savedIds.remove(spot.id);
      }
      _applySaveCount(spot.id, next ? 1 : -1);
      _notify();
      await _persistIds(savedIdsKey, _savedIds);
      await _persistSavedSpotsCache();

      try {
        final synced = await _repo.toggleSave(spot, saved: next);
        if (!synced) return false;

        try {
          await _refreshSingleSpot(spot.id);
        } catch (_) {
          // Keep optimistic update; the save itself succeeded.
        }
        _notify();
        return true;
      } catch (_) {
        if (wasSaved) {
          _savedIds.add(spot.id);
        } else {
          _savedIds.remove(spot.id);
        }
        _applySaveCount(spot.id, wasSaved ? 1 : -1);
        await _persistIds(savedIdsKey, _savedIds);
        _notify();
        return false;
      }
    });
  }

  void _applySaveCount(String spotId, int delta) {
    final index = _spots.indexWhere((s) => s.id == spotId);
    if (index == -1) return;
    final next = _spots[index].saveCount + delta;
    _spots[index] = _spots[index].copyWith(saveCount: next < 0 ? 0 : next);
  }

  /// Toggles a like. Serialized per spot to eliminate race conditions.
  Future<bool> toggleLike(Spot spot) {
    return _serializeForSpot(spot.id, () async {
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
          await _refreshSingleSpot(spot.id);
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
    });
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
    String? focalLength,
    bool? tripodFriendly,
    String? accessNote,
    Uint8List? photoBytes,
  }) async {
    final spot = await _repo.submitSpot(
      title: title,
      description: description,
      location: location,
      city: city,
      tags: tags,
      bestTime: bestTime,
      focalLength: focalLength,
      tripodFriendly: tripodFriendly,
      accessNote: accessNote,
      photoBytes: photoBytes,
    );

    if (!_spots.any((s) => s.id == spot.id)) {
      _spots = [spot, ..._spots];
    }
    _notify();
    return spot;
  }

  /// Updates an existing spot owned by the active user.
  Future<Spot> updateSpot({
    required String spotId,
    required String title,
    required String description,
    required String city,
    required List<String> tags,
    String? bestTime,
    String? focalLength,
    bool? tripodFriendly,
    String? accessNote,
  }) async {
    final updated = await _repo.updateSpot(
      spotId: spotId,
      title: title,
      description: description,
      city: city,
      tags: tags,
      bestTime: bestTime,
      focalLength: focalLength,
      tripodFriendly: tripodFriendly,
      accessNote: accessNote,
    );
    final idx = _spots.indexWhere((s) => s.id == spotId);
    if (idx != -1) {
      _spots[idx] = updated;
    }
    await _persistSavedSpotsCache();
    _notify();
    return updated;
  }

  /// Contributes an extra photo to an existing spot.
  Future<SpotPhoto> addSpotPhoto({
    required String spotId,
    required Uint8List photoBytes,
    String? caption,
  }) async {
    final photo = await _repo.addSpotPhoto(
      spotId: spotId,
      photoBytes: photoBytes,
      caption: caption,
    );
    final idx = _spots.indexWhere((s) => s.id == spotId);
    if (idx != -1) {
      final current = _spots[idx];
      if (!current.photos.any((p) => p.id == photo.id)) {
        _spots[idx] = current.copyWith(photos: [...current.photos, photo]);
      }
    }
    _notify();
    return photo;
  }

  /// Fetches additional geo-scoped spots around [center] and merges them into
  /// the in-memory catalog without duplicates.
  Future<void> loadNearbySpots(
    LatLng center, {
    double radiusKm = 50,
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      final fetched = await _repo.fetchSpotsNear(
        lat: center.latitude,
        lng: center.longitude,
        radiusKm: radiusKm,
        limit: limit,
        offset: offset,
      );
      if (fetched.isEmpty) return;
      final existingIds = {for (final s in _spots) s.id};
      var added = false;
      for (final s in fetched) {
        if (existingIds.add(s.id)) {
          _spots.add(s);
          added = true;
        }
      }
      if (added) _notify();
    } catch (_) {}
  }

  Future<void> _persistSavedSpotsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = _spots
          .where((s) => _savedIds.contains(s.id))
          .take(100)
          .map((s) => s.toCacheJson())
          .toList();
      await prefs.setString(savedSpotsCacheKey, jsonEncode(saved));
    } catch (_) {}
  }

  Future<List<Spot>> _readSavedSpotsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(savedSpotsCacheKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => Spot.fromCacheJson(Map<String, dynamic>.from(e)))
          .where((s) => s.id.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Deletes a spot owned by the active user.
  Future<void> deleteSpot(Spot spot) async {
    await _repo.deleteSpot(spot.id);
    _spots.removeWhere((s) => s.id == spot.id);
    _savedIds.remove(spot.id);
    _likedIds.remove(spot.id);
    _comments.remove(spot.id);
    await _persistIds(savedIdsKey, _savedIds);
    await _persistIds(likedIdsKey, _likedIds);
    _notify();
  }

  /// Deletes a comment owned by the active user.
  Future<void> deleteComment(String spotId, SpotComment comment) async {
    await _repo.deleteComment(comment.id);
    final list = _comments[spotId];
    if (list != null) {
      list.removeWhere((c) => c.id == comment.id);
    }
    final index = _spots.indexWhere((s) => s.id == spotId);
    if (index != -1) {
      final next = _spots[index].commentCount - 1;
      _spots[index] = _spots[index].copyWith(
        commentCount: next < 0 ? 0 : next,
      );
    }
    _notify();
  }

  /// Reports a spot or comment for moderation and optionally hides the spot
  /// from the user's feed immediately.
  Future<void> reportContent({
    required String targetType,
    required String targetId,
    required String reason,
    String? details,
    bool hideLocally = true,
  }) async {
    await _repo.reportContent(
      targetType: targetType,
      targetId: targetId,
      reason: reason,
      details: details,
    );
    if (hideLocally && targetType == 'spot') {
      _hiddenSpotIds.add(targetId);
      await _persistIds(hiddenSpotIdsKey, _hiddenSpotIds);
      _notify();
    }
  }

  /// Blocks a user so their spots and comments are immediately hidden.
  Future<void> blockUser(String userId) async {
    if (userId.isEmpty) return;
    _blockedUserIds.add(userId);
    await _persistIds(blockedUserIdsKey, _blockedUserIds);
    _notify();
    try {
      await _repo.blockUser(userId);
    } catch (_) {
      // Local block stays active even if offline.
    }
  }

  Future<void> unblockUser(String userId) async {
    _blockedUserIds.remove(userId);
    await _persistIds(blockedUserIdsKey, _blockedUserIds);
    _notify();
    try {
      await _repo.unblockUser(userId);
    } catch (_) {}
  }

  /// Clears all locally cached personalization signals (views and hidden list).
  Future<void> clearAllLocalActivity() async {
    _viewedIds.clear();
    _hiddenSpotIds.clear();
    await _persistIds(viewedIdsKey, _viewedIds);
    await _persistIds(hiddenSpotIdsKey, _hiddenSpotIds);
    _notify();
  }

  /// Produces a JSON summary of the user's locally stored data (Data Safety).
  String exportDataSummaryJson({
    required String displayName,
    required String email,
    required String bio,
    required String city,
  }) {
    final payload = {
      'exportedAt': DateTime.now().toIso8601String(),
      'profile': {
        'displayName': displayName,
        'email': email,
        'bio': bio,
        'city': city,
      },
      'activity': {
        'savedSpotIds': _savedIds.toList(),
        'likedSpotIds': _likedIds.toList(),
        'viewedSpotIds': _viewedIds.toList(),
        'submittedSpots': submittedSpots
            .map((s) => {
                  'id': s.id,
                  'title': s.title,
                  'city': s.city,
                  'tags': s.tags,
                  'latitude': s.location.latitude,
                  'longitude': s.location.longitude,
                })
            .toList(),
        'blockedUserIds': _blockedUserIds.toList(),
      },
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
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

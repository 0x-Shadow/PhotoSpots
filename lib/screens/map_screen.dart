import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/spot.dart';
import '../map/map_tile_layers.dart';
import '../map/tile_sources.dart';
import '../state/app_state.dart';
import '../state/location_outcome.dart';
import '../widgets/location_prompt.dart';
import '../state/settings_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import '../utils/actions.dart';
import '../utils/categories.dart';
import '../utils/format.dart';
import '../utils/navigation.dart';
import '../utils/ranking.dart';
import '../utils/share.dart';
import '../widgets/glass.dart';
import '../widgets/map_pin.dart';
import '../widgets/spot_image.dart';

enum _MapSort { recommended, nearest, topRated, saved }

/// Map screen — category pins, filters, sorting, and a floating spot card.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  /// A point requested by another screen (e.g. a spot's mini-map). The map
  /// consumes it on the next frame and clears it, so it never re-centres twice.
  static final ValueNotifier<LatLng?> focusRequest = ValueNotifier<LatLng?>(null);

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _mapController = MapController();
  final _searchController = TextEditingController();

  String? _selectedId;

  /// Category id from [spotFilters]; null means every category.
  String? _filterCategoryId;
  String _query = '';
  _MapSort _sort = _MapSort.recommended;
  bool _sortInitialized = false;
  bool _mapReady = false;
  LatLng? _lastCenteredLocation;
  DateTime? _lastMarkerTap;

  /// Marker culling & throttling. Rebuilding pins on every pinch-zoom frame
  /// causes lag when zooming in and out, so camera updates are coalesced via
  /// [_cameraThrottle] and settled cleanly when the gesture ends.
  LatLngBounds? _bufferedBounds;
  double _zoom = 12.5;
  bool _showPhotoPins = true;
  Timer? _cameraThrottle;
  MapCamera? _latestCamera;
  LatLng? _lastGeoFetchCenter;

  /// Memoized filtered+sorted list so pan/zoom frames never recompute Haversine
  /// distances over the entire catalog.
  List<Spot>? _memoSpots;
  String? _memoFilter;
  String? _memoQuery;
  _MapSort? _memoSort;
  LatLng? _memoOrigin;
  bool? _memoPersonalize;
  List<Spot> _memoResult = const [];

  /// The basemap actually rendered: the preferred style unless the probe
  /// found it unusable and the session fell back.
  MapStyle _activeStyle = TileSources.dark;
  String? _preferredUrl;
  String? _fallbackNotice;
  bool _tilesFailed = false;
  LatLng? _pendingFocus;
  final _tilesKey = GlobalKey<MapTileLayersState>();

  @override
  void initState() {
    super.initState();
    MapScreen.focusRequest.addListener(_onFocusRequested);
    final requested = MapScreen.focusRequest.value;
    if (requested != null) {
      MapScreen.focusRequest.value = null;
      _pendingFocus = requested;
    }
  }

  void _onFocusRequested() {
    final point = MapScreen.focusRequest.value;
    if (point == null) return;
    MapScreen.focusRequest.value = null;
    setState(() {
      _pendingFocus = point;
      _selectedId = null;
      _filterCategoryId = null;
      _query = '';
    });
    _moveMap(point, 15);
  }

  /// Re-reads the preferred style when Settings changes it, so a style picked
  /// there takes over and any session fallback is dropped.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = context.watch<SettingsState>();
    if (!_sortInitialized && settings.loaded) {
      _sortInitialized = true;
      _sort = switch (settings.defaultMapSort) {
        'nearest' => _MapSort.nearest,
        'top_rated' => _MapSort.topRated,
        'saved' => _MapSort.saved,
        _ => _MapSort.recommended,
      };
    }
    final preferred = settings.activeMapStyle;
    if (_preferredUrl == null || preferred.urlTemplate != _preferredUrl) {
      _preferredUrl = preferred.urlTemplate;
      _activeStyle = preferred;
      _fallbackNotice = null;
      _tilesFailed = false;
    }
  }

  /// The probe could not use the active style: either fall back to the street
  /// style or, when that has already failed too, show the failure panel.
  void _onFallback(String styleId) {
    final settings = context.read<SettingsState>();
    setState(() {
      if (styleId == _activeStyle.id || settings.mapStyle == styleId) {
        _tilesFailed = true;
        return;
      }
      _activeStyle = TileSources.byId(styleId, cartoApiKey: settings.cartoApiKey);
      _fallbackNotice = 'Basemap unavailable — using OpenStreetMap.';
      _tilesFailed = false;
    });
  }

  /// Re-probes the preferred style from scratch.
  void _retryTiles() {
    final settings = context.read<SettingsState>();
    setState(() {
      _activeStyle = settings.activeMapStyle;
      _preferredUrl = _activeStyle.urlTemplate;
      _fallbackNotice = null;
      _tilesFailed = false;
    });
    _tilesKey.currentState?.retry();
  }

  /// Moves the camera only once the map has been laid out, so an early tap or
  /// a location fix that arrives during startup cannot throw.
  void _moveMap(LatLng point, double zoom) {
    if (!_mapReady) return;
    try {
      _mapController.move(point, zoom);
    } catch (_) {
      // The controller is not attached yet; the next fix will center it.
    }
  }

  /// Centers on the first real location fix, but never fights the user's
  /// panning afterwards.
  void _centerOnUserOnce(AppState state) {
    if (!_mapReady || !state.hasUserLocation) return;
    final location = state.referenceLocation;
    if (_lastCenteredLocation == location) return;
    _lastCenteredLocation = location;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _moveMap(location, 13.5);
    });
  }

  /// The selected spot, but only while it is visible under the active filter
  /// and search query.
  /// Coalesces camera updates so pinch-zooming in/out never triggers 60fps
  /// marker rebuilds. Culling & zoom-level thresholds update at most ~7 times
  /// per second while moving, plus immediately once the gesture finishes.
  void _onCameraChanged(MapCamera camera) {
    if (!_mapReady) return;
    _latestCamera = camera;
    if (_cameraThrottle?.isActive ?? false) return;
    _cameraThrottle = Timer(const Duration(milliseconds: 140), () {
      if (mounted && _latestCamera != null) {
        _applyCameraState(_latestCamera!);
      }
    });
  }

  void _onMapEvent(MapEvent event) {
    if (!_mapReady) return;
    if (event is MapEventMoveEnd ||
        event is MapEventFlingAnimationEnd ||
        event is MapEventDoubleTapZoomEnd) {
      _cameraThrottle?.cancel();
      _applyCameraState(event.camera);
      _maybeFetchNearby(event.camera.center);
    }
  }

  void _maybeFetchNearby(LatLng center) {
    const distance = Distance();
    final prev = _lastGeoFetchCenter;
    if (prev != null &&
        distance.as(LengthUnit.Kilometer, prev, center) < 25) {
      return;
    }
    _lastGeoFetchCenter = center;
    context.read<AppState>().loadNearbySpots(center);
  }

  void _applyCameraState(MapCamera camera) {
    final photos = _photosAreUseful(camera.zoom);
    final zoomChangedCluster =
        (camera.zoom < 12.2) != (_zoom < 12.2) ||
        (camera.zoom - _zoom).abs() >= 0.8;
    final buffered = _bufferedBounds;
    final outsideBuffer =
        buffered == null || !buffered.containsBounds(camera.visibleBounds);
    if (!outsideBuffer && photos == _showPhotoPins && !zoomChangedCluster) {
      return;
    }
    setState(() {
      if (outsideBuffer) {
        _bufferedBounds = _buffered(camera.visibleBounds);
      }
      _zoom = camera.zoom;
      _showPhotoPins = photos;
    });
  }

  static bool _photosAreUseful(double zoom) => zoom >= 11.5;

  /// Pads the viewport generously so panning or minor zooming stays inside
  /// the already-built marker set without triggering setState.
  static LatLngBounds _buffered(LatLngBounds bounds) {
    final latPad = (bounds.north - bounds.south) * 0.6;
    final lngPad = (bounds.east - bounds.west) * 0.6;
    return LatLngBounds(
      LatLng(
        (bounds.south - latPad).clamp(-85.0, 85.0),
        (bounds.west - lngPad).clamp(-180.0, 180.0),
      ),
      LatLng(
        (bounds.north + latPad).clamp(-85.0, 85.0),
        (bounds.east + lngPad).clamp(-180.0, 180.0),
      ),
    );
  }

  /// Groups nearby pins into lightweight clusters when zoomed far out.
  ({List<Spot> singles, List<_SpotCluster> clusters}) _clusterOrPins(
    List<Spot> visible, {
    required bool enableClustering,
  }) {
    if (!enableClustering || _zoom >= 12.2 || visible.length <= 16) {
      return (singles: visible, clusters: const []);
    }

    final cellDeg = 0.035 * math.pow(2, (12.0 - _zoom).clamp(0.0, 7.0));
    final buckets = <String, List<Spot>>{};
    for (final spot in visible) {
      if (spot.id == _selectedId) continue;
      final gx = (spot.location.longitude / cellDeg).floor();
      final gy = (spot.location.latitude / cellDeg).floor();
      final key = '$gx:$gy';
      (buckets[key] ??= []).add(spot);
    }

    final singles = <Spot>[];
    final clusters = <_SpotCluster>[];
    for (final group in buckets.values) {
      if (group.length == 1) {
        singles.add(group.first);
      } else {
        var latSum = 0.0;
        var lngSum = 0.0;
        for (final s in group) {
          latSum += s.location.latitude;
          lngSum += s.location.longitude;
        }
        clusters.add(
          _SpotCluster(
            center: LatLng(latSum / group.length, lngSum / group.length),
            spots: group,
          ),
        );
      }
    }
    if (_selectedId != null) {
      for (final s in visible) {
        if (s.id == _selectedId) {
          singles.add(s);
          break;
        }
      }
    }
    return (singles: singles, clusters: clusters);
  }

  /// The subset of [spots] whose pins are worth building right now. The
  /// selected spot is always kept so its card never outlives its pin.
  List<Spot> _visibleInViewport(List<Spot> spots) {
    final bounds = _bufferedBounds;
    if (bounds == null) return spots;
    var visible = <Spot>[];
    for (final spot in spots) {
      if (bounds.contains(spot.location)) visible.add(spot);
    }
    // A dense city should never build thousands of pins in one frame. The best
    // rated survive; the selected spot is re-added below so its pin never
    // disappears from under its own card.
    if (visible.length > 260) {
      visible.sort((a, b) => b.rating.compareTo(a.rating));
      visible = visible.sublist(0, 260);
    }
    final selected = _selectedId;
    if (selected != null && !visible.any((spot) => spot.id == selected)) {
      for (final spot in spots) {
        if (spot.id == selected) {
          visible.add(spot);
          break;
        }
      }
    }
    return visible;
  }

  Spot? _selectedIn(List<Spot> spots) {
    if (_selectedId == null) return null;
    for (final spot in spots) {
      if (spot.id == _selectedId) return spot;
    }
    return null;
  }

  @override
  void dispose() {
    _cameraThrottle?.cancel();
    MapScreen.focusRequest.removeListener(_onFocusRequested);
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  List<Spot> _visible(AppState state) {
    final rawSpots = state.spots;
    final origin = state.referenceLocation;
    final personalize = state.personalizeFeed;
    if (identical(_memoSpots, rawSpots) &&
        _memoFilter == _filterCategoryId &&
        _memoQuery == _query &&
        _memoSort == _sort &&
        _memoOrigin == origin &&
        _memoPersonalize == personalize) {
      return _memoResult;
    }

    var list = spotsForFilter(rawSpots, _filterCategoryId).where((spot) {
      final query = _query.trim().toLowerCase();
      if (query.isEmpty) return true;
      return spot.title.toLowerCase().contains(query) ||
          spot.city.toLowerCase().contains(query) ||
          spot.tags.any((tag) => tag.toLowerCase().contains(query));
    }).toList();

    switch (_sort) {
      case _MapSort.recommended:
        list = SpotRanking.recommend(
          list,
          state.interestProfile,
          userLocation: state.hasReferenceFix ? origin : null,
          diversify: false,
        );
      case _MapSort.nearest:
        list.sort(
          (a, b) => state
              .distanceKm(origin, a)
              .compareTo(state.distanceKm(origin, b)),
        );
      case _MapSort.topRated:
        list.sort((a, b) => b.rating.compareTo(a.rating));
      case _MapSort.saved:
        list.sort((a, b) => b.saveCount.compareTo(a.saveCount));
    }

    _memoSpots = rawSpots;
    _memoFilter = _filterCategoryId;
    _memoQuery = _query;
    _memoSort = _sort;
    _memoOrigin = origin;
    _memoPersonalize = personalize;
    _memoResult = list;
    return list;
  }

  Future<void> _goToMyLocation() async {
    final state = context.read<AppState>();
    final outcome = await runLocationFlow(context, appState: state);
    if (!mounted) return;

    if (outcome != LocationOutcome.granted || state.userLocation == null) {
      return;
    }

    _moveMap(
      LatLng(state.userLocation!.latitude, state.userLocation!.longitude),
      14,
    );
  }

  Future<void> _openSortSheet() async {
    final selected = await showModalBottomSheet<_MapSort>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        Widget option(_MapSort value, IconData icon, String label) {
          final active = value == _sort;
          return ListTile(
            onTap: () => Navigator.of(sheetContext).pop(value),
            leading: Icon(
              icon,
              color: active ? AppColors.accent : AppColors.textSecondary,
            ),
            title: Text(
              label,
              style: TextStyle(
                color: active ? AppColors.textPrimary : AppColors.textSecondary,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            trailing: active
                ? const Icon(Icons.check_rounded, color: AppColors.accent)
                : null,
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Sort spots',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              option(
                _MapSort.recommended,
                Icons.auto_awesome_rounded,
                'Recommended for you',
              ),
              option(_MapSort.nearest, Icons.near_me_rounded, 'Nearest'),
              option(
                _MapSort.topRated,
                Icons.star_outline_rounded,
                'Top rated',
              ),
              option(
                _MapSort.saved,
                Icons.bookmark_outline_rounded,
                'Most saved',
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );

    if (selected != null && mounted) {
      setState(() => _sort = selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final settings = context.watch<SettingsState>();
    final allSpots = _visible(state);
    final viewportSpots = _visibleInViewport(allSpots);
    final grouped = _clusterOrPins(
      viewportSpots,
      enableClustering: settings.clusterMapPins,
    );
    final selected = _selectedIn(allSpots);
    final origin = state.referenceLocation;
    _centerOnUserOnce(state);

    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: state.hasUserLocation
                  ? origin
                  : AppState.fallbackCenter,
              initialZoom: 12.5,
              minZoom: 4,
              maxZoom: 18,
              backgroundColor: AppColors.mapBackground,
              interactionOptions: const InteractionOptions(
                flags:
                    InteractiveFlag.drag |
                    InteractiveFlag.pinchZoom |
                    InteractiveFlag.doubleTapZoom |
                    InteractiveFlag.flingAnimation,
              ),
              onPositionChanged: (camera, _) => _onCameraChanged(camera),
              onMapEvent: _onMapEvent,
              onMapReady: () {
                final camera = _mapController.camera;
                setState(() {
                  _mapReady = true;
                  _zoom = camera.zoom;
                  _bufferedBounds = _buffered(camera.visibleBounds);
                  _showPhotoPins = _photosAreUseful(camera.zoom);
                });
                final focus = _pendingFocus;
                if (focus != null) {
                  _pendingFocus = null;
                  _moveMap(focus, 15);
                } else if (state.hasUserLocation) {
                  _lastCenteredLocation = state.referenceLocation;
                  _moveMap(state.referenceLocation, 13.5);
                }
              },
              // Deliberately left empty — deselection is handled by tapping the
              // floating card's close button or by changing filters. The map's
              // onTap fires 250ms after a marker tap (to distinguish from
              // double-tap zoom), which would wrongly clear a just-made selection.
              onTap: (_, _) {
                if (_selectedId == null) return;
                // Marker taps set this; the map's own tap lags behind a marker
                // tap and must not dismiss the card the user just opened.
                final last = _lastMarkerTap;
                if (last != null &&
                    DateTime.now().difference(last) <
                        const Duration(milliseconds: 400)) {
                  return;
                }
                setState(() => _selectedId = null);
              },
            ),
            children: [
              MapTileLayers(
                key: _tilesKey,
                style: _activeStyle,
                onFallback: _onFallback,
              ),
              RepaintBoundary(
                child: MarkerLayer(
                  markers: [
                    if (state.userLocation != null)
                      Marker(
                        point: origin,
                        width: 34,
                        height: 34,
                        child: const PulsingLocationDot(),
                      ),
                    for (final cluster in grouped.clusters)
                      Marker(
                        point: cluster.center,
                        width: 44,
                        height: 44,
                        child: GestureDetector(
                          onTap: () => _fitSpots(cluster.spots),
                          child: SpotClusterPin(count: cluster.spots.length),
                        ),
                      ),
                    // Unselected pins first, then the selected one, so the active
                    // pin is never buried under a neighbour.
                    for (final spot in grouped.singles)
                      if (spot.id != _selectedId)
                        _spotMarker(
                          spot: spot,
                          selected: false,
                          showPhoto: settings.mapPhotoPins && _showPhotoPins,
                        ),
                    for (final spot in grouped.singles)
                      if (spot.id == _selectedId)
                        _spotMarker(
                          spot: spot,
                          selected: true,
                          showPhoto: settings.mapPhotoPins,
                        ),
                  ],
                ),
              ),
              MapAttribution(style: _activeStyle),
            ],
          ),
        ),

        // Floating glass search + sort.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: GlassPanel(
                      borderRadius: 999,
                      blur: 24,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      shadows: const [
                        BoxShadow(
                          color: Color(0x4D000000),
                          blurRadius: 18,
                          offset: Offset(0, 6),
                        ),
                      ],
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) => setState(() => _query = value),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14.5,
                        ),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search spots or cities',
                          hintStyle: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                          filled: false,
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: AppColors.textSecondary,
                            size: 20,
                          ),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _query = '');
                                    FocusManager.instance.primaryFocus
                                        ?.unfocus();
                                  },
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: AppColors.textSecondary,
                                    size: 18,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GlassIconButton(
                    icon: Icons.tune_rounded,
                    semanticLabel: 'Sort spots',
                    onTap: _openSortSheet,
                    size: 48,
                    iconSize: 19,
                  ),
                ],
              ),
            ),
          ),
        ),

        // One status slot so the loading chip, the fallback notice and the
        // failure panel can never stack on top of each other.
        Positioned(
          top: 116,
          left: 24,
          right: 24,
          child: _tilesFailed
              ? MapUnavailableView(
                  styleLabel: _activeStyle.label,
                  onRetry: _retryTiles,
                )
              : _fallbackNotice != null
              ? _FallbackNotice(
                  text: _fallbackNotice!,
                  onDismiss: () => setState(() => _fallbackNotice = null),
                )
              : IgnorePointer(
                  child: AnimatedOpacity(
                    duration: AppMotion.instant,
                    opacity: _mapReady ? 0 : 1,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xE61A1A1D),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppColors.hairline),
                        ),
                        child: Text(
                          'Loading your map…',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                    ),
                  ),
                ),
        ),

        // Filter chips.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 66),
              child: SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: spotFilters.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final filter = spotFilters[i];
                    final active = filter.categoryId == _filterCategoryId;
                    return GestureDetector(
                      onTap: () => setState(() {
                        // Tapping the active chip clears it; "All" always
                        // resets the filter.
                        _filterCategoryId =
                            filter.categoryId == null || active
                                ? null
                                : filter.categoryId;
                        if (_selectedId != null &&
                            !_visible(state).any((s) => s.id == _selectedId)) {
                          _selectedId = null;
                        }
                      }),
                      child: AnimatedContainer(
                        duration: AppMotion.instant,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        decoration: BoxDecoration(
                          color: active
                              ? AppColors.action
                              : const Color(0xD90F0F11),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: active
                                ? AppColors.action
                                : const Color(0x2EFFFFFF),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (active) ...[
                              Icon(
                                Icons.check_rounded,
                                size: 14,
                                color: AppColors.onAction,
                              ),
                              const SizedBox(width: 5),
                            ],
                            Text(
                              filter.label,
                              style: TextStyle(
                                color: active
                                    ? AppColors.onAction
                                    : AppColors.textSecondary,
                                fontSize: 12.5,
                                fontWeight: active
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),

        // One control column: fit all pins, share my location, go to my
        // location. It lifts above the spot card so the two never overlap.
        AnimatedPositioned(
          duration: AppMotion.quick,
          curve: AppMotion.easeOut,
          right: 16,
          bottom: selected != null ? 244 : 96,
          child: Column(
            children: [
              if (allSpots.length > 1)
                _MapControl(
                  icon: Icons.fit_screen_rounded,
                  semanticLabel: 'Fit all spots on the map',
                  onTap: () => _fitSpots(allSpots),
                ),
              if (allSpots.length > 1) const SizedBox(height: 8),
              if (state.hasReferenceFix)
                _MapControl(
                  icon: Icons.ios_share_rounded,
                  semanticLabel: 'Share my location',
                  onTap: () {
                    final point = state.referenceLocation;
                    shareLocationLink(
                      context,
                      lat: point.latitude,
                      lng: point.longitude,
                      title: 'My location',
                    );
                  },
                ),
              if (state.hasReferenceFix) const SizedBox(height: 8),
              _MapControl(
                icon: Icons.my_location_rounded,
                semanticLabel: 'Go to my location',
                loading: state.locationLoading,
                onTap: _goToMyLocation,
              ),
            ],
          ),
        ),

        if (allSpots.isEmpty)
          Positioned(
            top: 130,
            left: 24,
            right: 24,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: const Text(
                  'No spots match this filter',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
          ),

        // Floating spot card, animated in and out as the selection changes.
        Positioned(
          left: 0,
          right: 0,
          bottom: 92,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AnimatedSwitcher(
                  duration: AppMotion.quick,
                  switchInCurve: AppMotion.easeOut,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.12),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: selected == null
                      ? const SizedBox.shrink(key: ValueKey('no-selection'))
                      : _PlaceCard(
                          key: ValueKey(selected.id),
                          spot: selected,
                          distanceKm: state.hasUserLocation
                              ? state.distanceKm(origin, selected)
                              : null,
                          onClose: () => setState(() => _selectedId = null),
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Marker _spotMarker({
    required Spot spot,
    required bool selected,
    required bool showPhoto,
  }) {
    final width =
        selected ? MapPinMetrics.selectedWidth : MapPinMetrics.width;
    final height =
        selected ? MapPinMetrics.selectedHeight : MapPinMetrics.height;

    final pin = SpotPin(
      spot: spot,
      selected: selected,
      showPhoto: showPhoto,
    );

    // Only the active pin animates. A TweenAnimationBuilder per marker would
    // spawn a ticker for every pin on the map and rebuild them all on each
    // camera settle.
    final Widget child = selected
        ? TweenAnimationBuilder<double>(
            duration: AppMotion.quick,
            curve: AppMotion.easeOut,
            tween: Tween(begin: 0.82, end: 1.0),
            builder: (context, scale, pin) =>
                Transform.scale(scale: scale, child: pin),
            child: pin,
          )
        : pin;

    // The tail tip is the anchor, so the pin points at the coordinate.
    return Marker(
      point: spot.location,
      width: width,
      height: height,
      alignment: Alignment.topCenter,
      child: GestureDetector(
        onTap: () {
          FocusManager.instance.primaryFocus?.unfocus();
          _lastMarkerTap = DateTime.now();
          setState(() => _selectedId = spot.id);
          _moveMap(spot.location, 15);
        },
        behavior: HitTestBehavior.opaque,
        child: child,
      ),
    );
  }

  void _fitSpots(List<Spot> spots) {
    if (!_mapReady || spots.isEmpty) return;
    if (spots.length == 1) {
      _moveMap(spots.first.location, 15);
      return;
    }
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(
            spots.map((spot) => spot.location).toList(),
          ),
          padding: const EdgeInsets.all(64),
          maxZoom: 16,
        ),
      );
    } catch (_) {
      // A map that has not laid out yet can be fitted on the next build.
    }
  }
}

/// A single circular glass control on the map.
class _MapControl extends StatelessWidget {
  const _MapControl({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color(0x59000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: PressButton(
            semanticLabel: semanticLabel,
            onTap: onTap,
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0x29FFFFFF),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(icon, color: AppColors.textPrimary, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

/// A dismissible chip explaining that the basemap fell back for this session.
class _FallbackNotice extends StatelessWidget {
  const _FallbackNotice({required this.text, required this.onDismiss});

  final String text;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.only(left: 14, right: 4, top: 4, bottom: 4),
        decoration: BoxDecoration(
          color: const Color(0xE61A1A1D),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Semantics(
              button: true,
              label: 'Dismiss',
              child: InkWell(
                onTap: onDismiss,
                customBorder: const CircleBorder(),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: AppColors.textSecondary,
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

/// The floating preview for a tapped pin: a frosted card that leads with the
/// photo and shows the live engagement the ranking actually uses.
class _PlaceCard extends StatelessWidget {
  const _PlaceCard({
    super.key,
    required this.spot,
    this.distanceKm,
    this.onClose,
  });

  final Spot spot;
  final double? distanceKm;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final saved = state.isSaved(spot.id);
    final metric = context.watch<SettingsState>().metricUnits;
    final live = state.realtimeConnected;

    return GestureDetector(
      onTap: () => openSpot(context, spot),
      child: GlassPanel(
        borderRadius: 26,
        blur: 30,
        padding: const EdgeInsets.all(10),
        shadows: const [
          BoxShadow(
            color: Color(0x8C000000),
            blurRadius: 30,
            spreadRadius: -6,
            offset: Offset(0, 16),
          ),
        ],
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                width: 104,
                height: 112,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    SpotImage(
                      photo: spot.coverPhoto,
                      cacheWidth: 240,
                      iconSize: 26,
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x33000000), Color(0x00000000)],
                        ),
                      ),
                    ),
                    if (spot.bestTime != null)
                      Positioned(
                        left: 7,
                        bottom: 7,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xA6000000),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0x26FFFFFF)),
                          ),
                          child: Text(
                            spot.bestTime!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    spot.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(
                        Icons.place_rounded,
                        color: AppColors.textFaint,
                        size: 12,
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          [
                            if (spot.city.isNotEmpty) spot.city,
                            if (distanceKm != null)
                              formatDistance(distanceKm!, metric: metric),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                      if (live) ...[
                        const SizedBox(width: 7),
                        const _LiveBadge(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        color: AppColors.star,
                        size: 13,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        spot.rating.toStringAsFixed(1),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 10),
                      _StatChip(
                        icon: Icons.favorite_rounded,
                        value: formatCount(spot.likeCount),
                        tint: AppColors.like,
                      ),
                      const SizedBox(width: 8),
                      _StatChip(
                        icon: Icons.forum_rounded,
                        value: formatCount(spot.commentCount),
                        tint: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      _StatChip(
                        icon: Icons.bookmark_rounded,
                        value: formatCount(spot.saveCount),
                        tint: AppColors.textSecondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Text(
                        'View spot',
                        style: TextStyle(
                          color: AppColors.textPrimary.withValues(alpha: 0.9),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 3),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: AppColors.textSecondary,
                        size: 14,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              height: 112,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  PressButton(
                    semanticLabel: saved
                        ? 'Remove from saved'
                        : 'Save spot',
                    onTap: () => toggleSaveWithFeedback(context, spot),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: saved
                            ? AppColors.action
                            : const Color(0x1FFFFFFF),
                        border: Border.all(
                          color: saved
                              ? AppColors.action
                              : AppColors.glassBorder,
                        ),
                      ),
                      child: Icon(
                        saved
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_outline_rounded,
                        color: saved
                            ? AppColors.onAction
                            : AppColors.textPrimary,
                        size: 18,
                      ),
                    ),
                  ),
                  PressButton(
                    semanticLabel: 'Directions to ${spot.title}',
                    onTap: () => openDirections(context, spot),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0x14FFFFFF),
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: const Icon(
                        Icons.near_me_rounded,
                        color: AppColors.textPrimary,
                        size: 17,
                      ),
                    ),
                  ),
                  if (onClose != null)
                    PressButton(
                      semanticLabel: 'Close place card',
                      onTap: onClose!,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0x14FFFFFF),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: AppColors.textSecondary,
                          size: 17,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.value, required this.tint});

  final IconData icon;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11.5, color: tint),
        const SizedBox(width: 3),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// A quiet "live" marker: the community data on this card updates itself.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.success.withValues(alpha: 0.3),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 4,
            height: 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
              ),
            ),
          ),
          SizedBox(width: 4),
          Text(
            'Live',
            style: TextStyle(
              color: AppColors.success,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotCluster {
  const _SpotCluster({required this.center, required this.spots});

  final LatLng center;
  final List<Spot> spots;
}

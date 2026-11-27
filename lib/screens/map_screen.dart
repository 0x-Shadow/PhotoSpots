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
import '../utils/share.dart';
import '../widgets/map_pin.dart';
import '../widgets/spot_image.dart';

enum _MapSort { nearest, topRated, saved }

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
  _MapSort _sort = _MapSort.nearest;
  bool _mapReady = false;
  LatLng? _lastCenteredLocation;
  DateTime? _lastMarkerTap;

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
    final preferred = context.watch<SettingsState>().activeMapStyle;
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
  Spot? _selectedIn(List<Spot> spots) {
    if (_selectedId == null) return null;
    for (final spot in spots) {
      if (spot.id == _selectedId) return spot;
    }
    return null;
  }

  @override
  void dispose() {
    MapScreen.focusRequest.removeListener(_onFocusRequested);
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  List<Spot> _visible(AppState state) {
    var list = spotsForFilter(state.spots, _filterCategoryId).where((spot) {
      final query = _query.trim().toLowerCase();
      if (query.isEmpty) return true;
      return spot.title.toLowerCase().contains(query) ||
          spot.city.toLowerCase().contains(query) ||
          spot.tags.any((tag) => tag.toLowerCase().contains(query));
    }).toList();

    final origin = state.referenceLocation;
    switch (_sort) {
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
    final spots = _visible(state);
    final selected = _selectedIn(spots);
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
              onMapReady: () {
                setState(() => _mapReady = true);
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
              MarkerLayer(
                markers: [
                  if (state.userLocation != null)
                    Marker(
                      point: origin,
                      width: 34,
                      height: 34,
                      child: const PulsingLocationDot(),
                    ),
                  // Unselected pins first, then the selected one, so the active
                  // pin is never buried under a neighbour.
                  for (final spot in spots)
                    if (spot.id != _selectedId)
                      _spotMarker(
                        spot: spot,
                        selected: false,
                        showPhoto: settings.mapPhotoPins,
                      ),
                  for (final spot in spots)
                    if (spot.id == _selectedId)
                      _spotMarker(
                        spot: spot,
                        selected: true,
                        showPhoto: settings.mapPhotoPins,
                      ),
                ],
              ),
              MapAttribution(style: _activeStyle),
            ],
          ),
        ),

        // Search bar.
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
                        fillColor: const Color(0xF70F0F11),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
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
                                  FocusManager.instance.primaryFocus?.unfocus();
                                },
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: AppColors.textSecondary,
                                  size: 18,
                                ),
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(999),
                          borderSide: const BorderSide(
                            color: AppColors.hairline,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(999),
                          borderSide: const BorderSide(
                            color: AppColors.hairline,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(999),
                          borderSide: const BorderSide(
                            color: Color(0x4DFFFFFF),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PressButton(
                    semanticLabel: 'Sort spots',
                    onTap: _openSortSheet,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xF70F0F11),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: const Icon(
                        Icons.tune_rounded,
                        color: AppColors.textPrimary,
                        size: 19,
                      ),
                    ),
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
                              : const Color(0xF70F0F11),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: active
                                ? AppColors.action
                                : AppColors.hairline,
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

        // One glass control column: fit all pins, share my location, go to my
        // location. It lifts above the spot card so the two never overlap.
        AnimatedPositioned(
          duration: AppMotion.quick,
          curve: AppMotion.easeOut,
          right: 16,
          bottom: selected != null ? 188 : 76,
          child: Column(
            children: [
              if (spots.length > 1)
                _MapControl(
                  icon: Icons.fit_screen_rounded,
                  semanticLabel: 'Fit all spots on the map',
                  onTap: () => _fitSpots(spots),
                ),
              if (spots.length > 1) const SizedBox(height: 8),
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

        if (spots.isEmpty)
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
          bottom: 76,
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
        child: TweenAnimationBuilder<double>(
          duration: AppMotion.quick,
          curve: AppMotion.easeOut,
          tween: Tween(begin: selected ? 0.82 : 0.96, end: 1.0),
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: SpotPin(
            spot: spot,
            selected: selected,
            showPhoto: showPhoto,
          ),
        ),
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
    return PressButton(
      semanticLabel: semanticLabel,
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: const Color(0xF70F0F11),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x2EFFFFFF)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: loading
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, color: AppColors.textPrimary, size: 20),
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
    final saved = context.watch<AppState>().isSaved(spot.id);
    final metric = context.watch<SettingsState>().metricUnits;

    return GestureDetector(
      onTap: () => openSpot(context, spot),
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: const Color(0xF2121214),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.hairline),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SpotImage(photo: spot.coverPhoto, width: 64, height: 64),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    spot.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 5),
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
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        ' (${formatCount(spot.reviewCount)})',
                        style: const TextStyle(
                          color: AppColors.textFaint,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.near_me_rounded,
                        color: AppColors.textFaint,
                        size: 12,
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          distanceKm != null
                              ? formatDistance(distanceKm!, metric: metric)
                              : spot.city,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textFaint,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    spot.bestTime != null
                        ? 'Best view in ${spot.city} · ${spot.bestTime}'
                        : 'Best view in ${spot.city}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  button: true,
                  label: saved ? 'Remove from saved' : 'Save spot',
                  child: IconButton(
                    onPressed: () => toggleSaveWithFeedback(context, spot),
                    tooltip: saved ? 'Remove from saved' : 'Save spot',
                    constraints: const BoxConstraints(
                      minWidth: AppLayout.minTapTarget,
                      minHeight: 44,
                    ),
                    icon: Icon(
                      saved
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_outline_rounded,
                      color: saved ? AppColors.star : AppColors.textSecondary,
                      size: 21,
                    ),
                  ),
                ),
                if (onClose != null)
                  Semantics(
                    button: true,
                    label: 'Close place card',
                    child: IconButton(
                      onPressed: onClose,
                      tooltip: 'Close',
                      constraints: const BoxConstraints(
                        minWidth: AppLayout.minTapTarget,
                        minHeight: 40,
                      ),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.textFaint,
                        size: 18,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

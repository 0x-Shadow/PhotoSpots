import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../data/spot_repository.dart';
import '../map/map_tile_layers.dart';
import '../map/tile_sources.dart';
import '../services/geocoding.dart';
import '../state/app_state.dart';
import '../state/location_outcome.dart';
import '../state/settings_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/location_prompt.dart';
import '../widgets/spot_details_form.dart';

/// Three deliberate steps: photo, location, details. The city comes from the
/// pin, never from a hardcoded default.
class SubmitScreen extends StatefulWidget {
  const SubmitScreen({super.key, this.initialStep = 0});

  /// Optional entry step — tests use it to reach the map without faking the
  /// platform photo picker.
  final int initialStep;

  /// A cached user fix wins; otherwise the map's own centre is used. The demo
  /// seed is only a last resort for a map that has not laid out yet.
  static LatLng initialPin(AppState state, {LatLng? mapCenter}) {
    if (state.hasCachedFix) return state.referenceLocation;
    return mapCenter ?? AppState.fallbackCenter;
  }

  @override
  State<SubmitScreen> createState() => _SubmitScreenState();
}

class _SubmitScreenState extends State<SubmitScreen> {
  int _step = 0;

  /// True when the pin came from the demo seed rather than the user's last
  /// fix, so the UI can say so instead of implying a real location.
  bool _usingDemoSeed = false;

  final _draft = SpotDraftController();
  final _geocoder = const GeocodingService();
  final _searchController = TextEditingController();
  final _mapController = MapController();

  Timer? _searchTimer;
  Timer? _reverseTimer;

  Uint8List? _photoBytes;
  LatLng _pinned = AppState.fallbackCenter;
  String _address = '';
  bool _cityManual = false;
  bool _searching = false;
  bool _streetFallback = false;
  bool _submitting = false;
  List<PlaceSuggestion> _suggestions = const [];

  static const _stepTitles = ['Photo', 'Location', 'Details'];

  @override
  void initState() {
    super.initState();
    _step = widget.initialStep;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<AppState>();
      setState(() {
        _pinned = SubmitScreen.initialPin(state);
        _usingDemoSeed = !state.hasCachedFix;
      });
    });
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _reverseTimer?.cancel();
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  bool get _canProceed => switch (_step) {
        0 => _photoBytes != null,
        1 => true,
        _ => _draft.canPublish,
      };

  Future<void> _pickPhoto(ImageSource source) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photoBytes = bytes;
        // The system picker is already a deliberate decision; do not ask for
        // another confirmation tap before continuing.
        if (_step == 0) _step = 1;
      });
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            source == ImageSource.camera
                ? 'Could not open the camera.'
                : 'Could not open the photo picker.',
          ),
        ),
      );
    }
  }

  /// Moves the pin and schedules a reverse lookup. A failed lookup leaves the
  /// pin in place and reveals the manual city field.
  void _setPin(LatLng point) {
    _reverseTimer?.cancel();
    setState(() {
      _pinned = point;
      _address = '';
      _cityManual = false;
      _draft.city = '';
    });
    _reverseTimer = Timer(const Duration(milliseconds: 400), () async {
      final place = await _geocoder.reverse(point.latitude, point.longitude);
      if (!mounted || _pinned != point) return;
      setState(() {
        if (place == null) {
          _cityManual = true;
          return;
        }
        _address = place.label;
        _draft.city = place.city;
        _cityManual = place.city.isEmpty;
        if (_draft.name.isEmpty) {
          _draft.name = place.label.split(',').first.trim();
        }
      });
    });
  }

  void _search(String query) {
    _searchTimer?.cancel();
    if (query.trim().isEmpty) {
      setState(() => _suggestions = const []);
      return;
    }
    _searchTimer = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _searching = true);
      final results = await _geocoder.search(query);
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _searching = false;
      });
    });
  }

  void _chooseSuggestion(PlaceSuggestion suggestion) {
    final point = LatLng(suggestion.lat, suggestion.lng);
    _mapController.move(point, 15);
    _reverseTimer?.cancel();
    setState(() {
      _pinned = point;
      _address = suggestion.label;
      _suggestions = const [];
      _cityManual = suggestion.city.isEmpty;
      _draft
        ..city = suggestion.city
        ..name = suggestion.label.split(',').first.trim();
    });
  }

  Future<void> _useMyLocation() async {
    final state = context.read<AppState>();
    final outcome = await runLocationFlow(context, appState: state);
    if (!mounted || outcome != LocationOutcome.granted) return;
    final position = state.userLocation;
    if (position == null) return;
    final point = LatLng(position.latitude, position.longitude);
    _mapController.move(point, 15);
    _setPin(point);
  }

  Future<void> _confirmPublish() async {
    if (_submitting || !_draft.canPublish) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surfaceElevated,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 6, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ready to publish?', style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 14),
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: _photoBytes == null
                          ? const Icon(Icons.image_rounded,
                              color: AppColors.textFaint, size: 28)
                          : Image.memory(_photoBytes!, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_draft.name,
                            style: Theme.of(sheetContext).textTheme.titleMedium),
                        const SizedBox(height: 3),
                        Text(
                          _draft.city.isEmpty
                              ? 'City not set'
                              : _draft.city,
                          style: Theme.of(sheetContext).textTheme.bodySmall,
                        ),
                        if (_address.isNotEmpty)
                          Text(
                            _address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(sheetContext).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop(false),
                      child: const Text('Keep editing'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PressButton(
                      semanticLabel: 'Publish spot',
                      onTap: () => Navigator.of(sheetContext).pop(true),
                      child: Container(
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.action,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          'Publish',
                          style: Theme.of(sheetContext)
                              .textTheme
                              .labelLarge
                              ?.copyWith(
                                color: AppColors.onAction,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    await _publish();
  }

  Future<void> _publish() async {
    if (_submitting) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _submitting = true);

    try {
      await context.read<AppState>().submitSpot(
            title: _draft.name.trim(),
            description: _draft.tip.trim().isEmpty
                ? 'A photo spot shared by the ${AppInfo.name} community.'
                : _draft.tip.trim(),
            location: _pinned,
            city: _draft.city.trim(),
            tags: _draft.tags.toList(),
            bestTime: _draft.bestTime,
            photoBytes: _photoBytes,
          );
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Spot added to the map')),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            error is AppException
                ? error.message
                : 'Could not publish this spot. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: PressButton(
            semanticLabel: _step == 0 ? 'Close' : 'Back',
            onTap: _back,
            child: Container(
              width: 44,
              height: 44,
              margin: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(
                color: const Color(0x14FFFFFF),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.hairline),
              ),
              child: Icon(
                _step == 0 ? Icons.close_rounded : Icons.arrow_back_rounded,
                color: AppColors.textPrimary,
                size: 20,
              ),
            ),
          ),
          title: Text(_stepTitles[_step]),
          centerTitle: true,
        ),
        body: SafeArea(
          child: ResponsiveBody(
            child: Column(
              children: [
                _ProgressBar(step: _step, titles: _stepTitles),
                if (_step == 2)
                  Expanded(
                    child: SpotDetailsForm(
                      controller: _draft,
                      initialName: _draft.name,
                      initialCity: _draft.city,
                      cityEditable: _cityManual,
                      onPublish: _confirmPublish,
                    ),
                  )
                else ...[
                  Expanded(child: _stepContent()),
                  _BottomBar(
                    step: _step,
                    enabled: _canProceed && !_submitting,
                    onNext: () {
                      if (_canProceed) setState(() => _step++);
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepContent() => switch (_step) {
        0 => _PhotoStep(
            photoBytes: _photoBytes,
            onPick: _pickPhoto,
            onClear: () => setState(() => _photoBytes = null),
          ),
        _ => _LocationStep(
            pinned: _pinned,
            usingDemoSeed: _usingDemoSeed,
            address: _address,
            city: _draft.city,
            cityEditable: _cityManual,
            suggestions: _suggestions,
            searching: _searching,
            onSearch: _search,
            onChoose: _chooseSuggestion,
            onPinMoved: _setPin,
            onUseMyLocation: _useMyLocation,
            onCityChanged: (value) => setState(() => _draft.city = value),
            streetFallback: _streetFallback,
            onFallback: () {
              if (_streetFallback) return;
              setState(() => _streetFallback = true);
            },
            mapController: _mapController,
            searchController: _searchController,
          ),
      };
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.step, required this.titles});

  final int step;
  final List<String> titles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        children: [
          Row(
            children: [
              for (var i = 0; i < titles.length; i++)
                Expanded(
                  child: AnimatedContainer(
                    duration: AppMotion.instant,
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i <= step ? AppColors.action : AppColors.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < titles.length; i++)
                Expanded(
                  child: Text(
                    titles[i],
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.labelMedium?.copyWith(
                      color: i <= step
                          ? AppColors.textPrimary
                          : AppColors.textFaint,
                      fontWeight:
                          i <= step ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.step,
    required this.enabled,
    required this.onNext,
  });

  final int step;
  final bool enabled;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: PressButton(
          semanticLabel: 'Next step',
          enabled: enabled,
          onTap: onNext,
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: enabled ? AppColors.action : AppColors.hairline,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              step == 0 ? 'Next' : 'Continue',
              style: theme.labelLarge?.copyWith(
                color:
                    enabled ? AppColors.onAction : AppColors.textFaint,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoStep extends StatelessWidget {
  const _PhotoStep({
    required this.photoBytes,
    required this.onPick,
    required this.onClear,
  });

  final Uint8List? photoBytes;
  final ValueChanged<ImageSource> onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      children: [
        Text('Show the spot at its best', style: theme.titleMedium),
        const SizedBox(height: 5),
        Text(
          'One photo is required. Pick your best shot — it becomes the cover.',
          style: theme.bodySmall,
        ),
        const SizedBox(height: 18),
        GestureDetector(
          onTap: () => onPick(ImageSource.gallery),
          child: Container(
            height: 300,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: photoBytes != null
                    ? AppColors.accentSoft
                    : AppColors.hairline,
              ),
            ),
            child: photoBytes == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_a_photo_rounded,
                          color: AppColors.textSecondary, size: 42),
                      const SizedBox(height: 12),
                      Text('Add your best shot', style: theme.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        'JPG or PNG · one photo required',
                        style: theme.bodySmall,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _PhotoSourceButton(
                            icon: Icons.photo_library_rounded,
                            label: 'Gallery',
                            filled: true,
                            onTap: () => onPick(ImageSource.gallery),
                          ),
                          const SizedBox(width: 10),
                          _PhotoSourceButton(
                            icon: Icons.photo_camera_rounded,
                            label: 'Camera',
                            onTap: () => onPick(ImageSource.camera),
                          ),
                        ],
                      ),
                    ],
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(photoBytes!, fit: BoxFit.cover),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Semantics(
                          button: true,
                          label: 'Remove photo',
                          child: IconButton(
                            onPressed: onClear,
                            tooltip: 'Remove photo',
                            icon: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close_rounded,
                                  color: Colors.white, size: 19),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          photoBytes == null
              ? 'A photo is required to continue'
              : 'Looking good — continue when ready.',
          style: theme.bodySmall?.copyWith(
            color: photoBytes == null ? AppColors.textFaint : AppColors.success,
          ),
        ),
      ],
    );
  }
}

class _PhotoSourceButton extends StatelessWidget {
  const _PhotoSourceButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return PressButton(
      semanticLabel: label == 'Camera'
          ? 'Take a photo with the camera'
          : 'Choose a photo from the gallery',
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: filled ? AppColors.action : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: filled ? AppColors.action : AppColors.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 17,
                color: filled ? AppColors.onAction : AppColors.textPrimary),
            const SizedBox(width: 7),
            Text(
              label,
              style: theme.labelLarge?.copyWith(
                color: filled ? AppColors.onAction : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Map-first location step: search, tap to place, and an address derived from
/// the pin. A failed reverse lookup reveals a manual city field.
class _LocationStep extends StatelessWidget {
  const _LocationStep({
    required this.pinned,
    required this.usingDemoSeed,
    required this.address,
    required this.city,
    required this.cityEditable,
    required this.suggestions,
    required this.searching,
    required this.onSearch,
    required this.onChoose,
    required this.onPinMoved,
    required this.onUseMyLocation,
    required this.onCityChanged,
    required this.streetFallback,
    required this.onFallback,
    required this.mapController,
    required this.searchController,
  });

  final LatLng pinned;
  final bool usingDemoSeed;
  final String address;
  final String city;
  final bool cityEditable;
  final List<PlaceSuggestion> suggestions;
  final bool searching;
  final ValueChanged<String> onSearch;
  final ValueChanged<PlaceSuggestion> onChoose;
  final ValueChanged<LatLng> onPinMoved;
  final VoidCallback onUseMyLocation;
  final ValueChanged<String> onCityChanged;
  final bool streetFallback;
  final VoidCallback onFallback;
  final MapController mapController;
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final style = streetFallback
        ? TileSources.street
        : context.watch<SettingsState>().activeMapStyle;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        if (usingDemoSeed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'No saved location yet — showing the demo area.',
              style: theme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        TextField(
          controller: searchController,
          onChanged: onSearch,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search a place',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: searching
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Column(
              children: [
                for (final suggestion in suggestions)
                  InkWell(
                    onTap: () => onChoose(suggestion),
                    child: ListTile(
                      leading: const Icon(Icons.place_outlined,
                          color: AppColors.accent, size: 20),
                      title: Text(suggestion.label, style: theme.bodyLarge),
                      subtitle: suggestion.city.isEmpty
                          ? null
                          : Text(suggestion.city, style: theme.bodySmall),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: 320,
            child: FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: pinned,
                initialZoom: 14,
                maxZoom: 18,
                backgroundColor: AppColors.mapBackground,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.drag |
                      InteractiveFlag.pinchZoom |
                      InteractiveFlag.doubleTapZoom |
                      InteractiveFlag.flingAnimation,
                ),
                onTap: (_, point) => onPinMoved(point),
                onPositionChanged: (camera, _) {
                  final next = camera.center;
                  if ((next.latitude - pinned.latitude).abs() > 1e-6 ||
                      (next.longitude - pinned.longitude).abs() > 1e-6) {
                    onPinMoved(next);
                  }
                },
              ),
              children: [
                MapTileLayers(style: style, onFallback: (_) => onFallback()),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: pinned,
                      width: 36,
                      height: 36,
                      child: const Icon(
                        Icons.place_rounded,
                        color: AppColors.accent,
                        size: 34,
                      ),
                    ),
                  ],
                ),
                MapAttribution(style: style),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                address.isEmpty ? 'Tap or drag the map to place the pin' : address,
                style: theme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: onUseMyLocation,
              icon: const Icon(Icons.my_location_rounded, size: 16),
              label: const Text('Use my location'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                textStyle: theme.labelLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${pinned.latitude.toStringAsFixed(5)}, '
          '${pinned.longitude.toStringAsFixed(5)}',
          style: theme.bodySmall?.copyWith(color: AppColors.textFaint),
        ),
        if (cityEditable) ...[
          const SizedBox(height: 12),
          TextField(
            onChanged: onCityChanged,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'City',
              hintText: 'Enter the nearest city',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Address lookup failed — type the city yourself.',
            style: theme.bodySmall?.copyWith(color: AppColors.danger),
          ),
        ] else if (city.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('City: $city', style: theme.bodySmall),
        ],
      ],
    );
  }
}

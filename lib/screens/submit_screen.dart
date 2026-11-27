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
import '../services/photo_metadata.dart';
import '../state/app_state.dart';
import '../state/location_outcome.dart';
import '../state/settings_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/location_prompt.dart';
import '../widgets/map_pin.dart';
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
  PhotoLocation? _photoLocation;
  LatLng _pinned = AppState.fallbackCenter;
  String _address = '';
  bool _cityManual = false;
  bool _searching = false;
  bool _searchFailed = false;
  bool _searchEmpty = false;
  bool _resolving = false;
  bool _mapReadyForPin = false;
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
    final navigator = Navigator.of(context);
    try {
      // Deliberately not downscaling or re-compressing: re-encoding can strip
      // the EXIF block that tells us where the photo was taken.
      final picked = await ImagePicker().pickImage(source: source);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final gps = PhotoMetadata.readGps(bytes);
      if (!mounted) return;
      setState(() {
        _photoBytes = bytes;
        _photoLocation = gps;
        // The system picker is already a deliberate decision; do not ask for
        // another confirmation tap before continuing.
        if (_step == 0) _step = 1;
      });
      if (gps != null) _applyPhotoLocation(gps);
    } catch (_) {
      if (!navigator.mounted) return;
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

  /// Places the pin where the photo was taken and fills the address from it.
  void _applyPhotoLocation(PhotoLocation gps) {
    final point = LatLng(gps.latitude, gps.longitude);
    setState(() {
      _pinned = point;
      _address = '';
      _resolving = true;
      _usingDemoSeed = false;
      _cityManual = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapReadyForPin) return;
      try {
        _mapController.move(point, 15);
      } catch (_) {
        // The map attaches on the next frame; its initial centre is the pin.
      }
    });
    _resolveAddress(point);
  }

  /// The map settled somewhere new. Only real changes move the pin, so
  /// programmatic jumps never clear a city the user just chose.
  void _onCenterChanged(LatLng point) {
    if ((_pinned.latitude - point.latitude).abs() < 1e-7 &&
        (_pinned.longitude - point.longitude).abs() < 1e-7) {
      return;
    }
    setState(() {
      _pinned = point;
      _address = '';
      _resolving = true;
    });
    _resolveAddress(point);
  }

  /// Debounced reverse lookup. A failure keeps the pin and reveals the manual
  /// city field rather than blocking publishing.
  void _resolveAddress(LatLng point) {
    _reverseTimer?.cancel();
    _reverseTimer = Timer(const Duration(milliseconds: 450), () async {
      final place = await _geocoder.reverse(point.latitude, point.longitude);
      if (!mounted) return;
      if ((_pinned.latitude - point.latitude).abs() > 1e-7 ||
          (_pinned.longitude - point.longitude).abs() > 1e-7) {
        return;
      }
      setState(() {
        _resolving = false;
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
      setState(() {
        _suggestions = const [];
        _searchFailed = false;
        _searchEmpty = false;
      });
      return;
    }
    _searchTimer = Timer(const Duration(milliseconds: 450), () async {
      setState(() {
        _searching = true;
        _searchFailed = false;
        _searchEmpty = false;
      });
      final result = await _geocoder.searchPlaces(query);
      if (!mounted) return;
      setState(() {
        _suggestions = result.results;
        _searching = false;
        _searchFailed = result.failed;
        _searchEmpty = result.results.isEmpty && !result.failed;
      });
    });
  }

  void _chooseSuggestion(PlaceSuggestion suggestion) {
    final point = LatLng(suggestion.lat, suggestion.lng);
    _reverseTimer?.cancel();
    setState(() {
      _pinned = point;
      _address = suggestion.label;
      _suggestions = const [];
      _searchEmpty = false;
      _searchFailed = false;
      _resolving = false;
      _cityManual = suggestion.city.isEmpty;
      _draft
        ..city = suggestion.city
        ..name = suggestion.label.split(',').first.trim();
    });
    try {
      _mapController.move(point, 15);
    } catch (_) {
      // The controller attaches once the map lays out.
    }
  }

  Future<void> _useMyLocation() async {
    final state = context.read<AppState>();
    final outcome = await runLocationFlow(context, appState: state);
    if (!mounted || outcome != LocationOutcome.granted) return;
    final position = state.userLocation;
    if (position == null) return;
    final point = LatLng(position.latitude, position.longitude);
    setState(() {
      _pinned = point;
      _address = '';
      _resolving = true;
      _usingDemoSeed = false;
    });
    try {
      _mapController.move(point, 15);
    } catch (_) {
      // The controller attaches once the map lays out.
    }
    _resolveAddress(point);
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
                      location: _pinned,
                      address: _address,
                      cityEditable: _cityManual,
                      onChangeLocation: () => setState(() => _step = 1),
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
            photoLocation: _photoLocation,
            onPick: _pickPhoto,
            onClear: () => setState(() {
              _photoBytes = null;
              _photoLocation = null;
            }),
          ),
        _ => _LocationStep(
            pinned: _pinned,
            usingDemoSeed: _usingDemoSeed,
            address: _address,
            city: _draft.city,
            cityEditable: _cityManual,
            photoDetected: _photoLocation != null,
            suggestions: _suggestions,
            searching: _searching,
            searchFailed: _searchFailed,
            searchEmpty: _searchEmpty,
            resolving: _resolving,
            onSearch: _search,
            onChoose: _chooseSuggestion,
            onCenterChanged: _onCenterChanged,
            onTapPoint: (point) {
              try {
                _mapController.move(point, _mapController.camera.zoom);
              } catch (_) {
                // The controller attaches once the map lays out.
              }
            },
            onMapReady: () => _mapReadyForPin = true,
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

/// Step one: one clear photo card, the two ways to add it, and a note about
/// the location we can read from the file.
class _PhotoStep extends StatelessWidget {
  const _PhotoStep({
    required this.photoBytes,
    required this.photoLocation,
    required this.onPick,
    required this.onClear,
  });

  final Uint8List? photoBytes;
  final PhotoLocation? photoLocation;
  final ValueChanged<ImageSource> onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final hasPhoto = photoBytes != null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      children: [
        Text('Show the spot at its best', style: theme.titleMedium),
        const SizedBox(height: 5),
        Text(
          hasPhoto
              ? 'Swap it anytime before you publish.'
              : 'One photo becomes the cover of the spot.',
          style: theme.bodySmall,
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: AppMotion.quick,
          switchInCurve: AppMotion.easeOut,
          child: hasPhoto
              ? _PhotoPreview(
                  key: const ValueKey('preview'),
                  bytes: photoBytes!,
                  onClear: onClear,
                )
              : _PhotoDropzone(
                  key: const ValueKey('dropzone'),
                  onPick: onPick,
                ),
        ),
        const SizedBox(height: 14),
        _PhotoLocationNote(
          hasPhoto: hasPhoto,
          location: photoLocation,
        ),
        const SizedBox(height: 20),
        if (hasPhoto)
          Row(
            children: [
              Expanded(
                child: _PhotoSourceButton(
                  icon: Icons.photo_library_rounded,
                  label: 'Replace',
                  filled: true,
                  onTap: () => onPick(ImageSource.gallery),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PhotoSourceButton(
                  icon: Icons.photo_camera_rounded,
                  label: 'Retake',
                  onTap: () => onPick(ImageSource.camera),
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: _PhotoSourceButton(
                  icon: Icons.photo_library_rounded,
                  label: 'Choose photo',
                  filled: true,
                  onTap: () => onPick(ImageSource.gallery),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PhotoSourceButton(
                  icon: Icons.photo_camera_rounded,
                  label: 'Camera',
                  onTap: () => onPick(ImageSource.camera),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _PhotoDropzone extends StatelessWidget {
  const _PhotoDropzone({super.key, required this.onPick});

  final ValueChanged<ImageSource> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: () => onPick(ImageSource.gallery),
      child: Container(
        height: 316,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF19191D), Color(0xFF0E0E10)],
          ),
          border: Border.all(color: const Color(0x33FFFFFF), width: 1.2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accentSoft,
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.45),
                ),
              ),
              child: const Icon(
                Icons.add_a_photo_rounded,
                color: AppColors.accent,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text('Add your cover photo', style: theme.titleSmall),
            const SizedBox(height: 5),
            Text('JPEG or PNG · tap to browse', style: theme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({
    super.key,
    required this.bytes,
    required this.onClear,
  });

  final Uint8List bytes;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 316,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              bytes,
              fit: BoxFit.cover,
              cacheWidth: 1200,
              errorBuilder: (_, _, _) => const ColoredBox(
                color: AppColors.surfaceElevated,
                child: Center(
                  child: Icon(
                    Icons.broken_image_rounded,
                    color: AppColors.textFaint,
                    size: 34,
                  ),
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x4D000000), Color(0x00000000), Color(0x66000000)],
                ),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0x99000000),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0x26FFFFFF)),
                ),
                child: const Text(
                  'COVER PHOTO',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
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
                      color: Color(0x99000000),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 19,
                    ),
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

class _PhotoLocationNote extends StatelessWidget {
  const _PhotoLocationNote({
    required this.hasPhoto,
    required this.location,
  });

  final bool hasPhoto;
  final PhotoLocation? location;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final found = location != null;
    final icon = !hasPhoto
        ? Icons.auto_awesome_rounded
        : found
            ? Icons.location_on_rounded
            : Icons.location_off_rounded;
    final color = found ? AppColors.success : AppColors.textSecondary;
    final text = !hasPhoto
        ? 'If your photo has GPS data, we place the pin for you.'
        : found
            ? 'Location found in this photo — set on the next step.'
            : 'No location saved in this photo. Drop the pin yourself.';

    return Row(
      children: [
        Icon(icon, color: color, size: 17),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.bodySmall?.copyWith(color: color),
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
        height: 48,
        decoration: BoxDecoration(
          color: filled ? AppColors.action : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: filled ? AppColors.action : AppColors.hairline,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 17,
              color: filled ? AppColors.onAction : AppColors.textPrimary,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.labelLarge?.copyWith(
                  color: filled ? AppColors.onAction : AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Step two: search, a fixed centre pin the user can drag the map under, and an
/// address that always describes the pin.
class _LocationStep extends StatelessWidget {
  const _LocationStep({
    required this.pinned,
    required this.usingDemoSeed,
    required this.address,
    required this.city,
    required this.cityEditable,
    required this.photoDetected,
    required this.suggestions,
    required this.searching,
    required this.searchFailed,
    required this.searchEmpty,
    required this.resolving,
    required this.onSearch,
    required this.onChoose,
    required this.onCenterChanged,
    required this.onTapPoint,
    required this.onMapReady,
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
  final bool photoDetected;
  final List<PlaceSuggestion> suggestions;
  final bool searching;
  final bool searchFailed;
  final bool searchEmpty;
  final bool resolving;
  final ValueChanged<String> onSearch;
  final ValueChanged<PlaceSuggestion> onChoose;
  final ValueChanged<LatLng> onCenterChanged;
  final ValueChanged<LatLng> onTapPoint;
  final VoidCallback onMapReady;
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
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      children: [
        if (usingDemoSeed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: AppColors.textFaint,
                  size: 15,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'No saved location yet — showing the demo area.',
                    style: theme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        TextField(
          controller: searchController,
          onChanged: onSearch,
          textInputAction: TextInputAction.search,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14.5,
          ),
          decoration: InputDecoration(
            hintText: 'Search a place, city, or address',
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
                : (searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          searchController.clear();
                          onSearch('');
                        },
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.textFaint,
                          size: 18,
                        ),
                      )),
          ),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 232),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.hairline),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: suggestions.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: AppColors.hairline),
                itemBuilder: (_, i) {
                  final suggestion = suggestions[i];
                  return InkWell(
                    onTap: () => onChoose(suggestion),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.place_outlined,
                            color: AppColors.accent,
                            size: 19,
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  suggestion.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.bodyLarge?.copyWith(
                                    color: AppColors.textPrimary,
                                    fontSize: 14,
                                  ),
                                ),
                                if (suggestion.city.isNotEmpty)
                                  Text(
                                    suggestion.city,
                                    style: theme.bodySmall,
                                  ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.north_west_rounded,
                            color: AppColors.textFaint,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
        if (searchFailed || searchEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                searchFailed
                    ? Icons.cloud_off_rounded
                    : Icons.search_off_rounded,
                color: AppColors.textFaint,
                size: 15,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  searchFailed
                      ? 'Search is unavailable right now. Drag the map to the spot instead.'
                      : 'No places found. Try a city name, or drag the map.',
                  style: theme.bodySmall,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(
            height: 322,
            child: Stack(
              children: [
                Positioned.fill(
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
                      onMapReady: onMapReady,
                      onTap: (_, point) => onTapPoint(point),
                      onPositionChanged: (camera, _) =>
                          onCenterChanged(camera.center),
                    ),
                    children: [
                      MapTileLayers(
                        style: style,
                        onFallback: (_) => onFallback(),
                      ),
                      MapAttribution(style: style),
                    ],
                  ),
                ),
                // The pin sits at the map centre; dragging the map moves the
                // spot, which is far easier than hitting a small marker.
                const Positioned.fill(
                  child: IgnorePointer(
                    child: Align(
                      alignment: Alignment.center,
                      child: FractionalTranslation(
                        translation: Offset(0, -0.5),
                        child: SpotPinPreview(),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: PressButton(
                    semanticLabel: 'Use my location',
                    onTap: onUseMyLocation,
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xF20F0F11),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0x33FFFFFF)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x59000000),
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.my_location_rounded,
                            color: AppColors.textPrimary,
                            size: 17,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            'My location',
                            style: theme.labelLarge?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (photoDetected)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on_rounded,
                  color: AppColors.success,
                  size: 16,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Pin placed from your photo’s GPS data. Drag the map to adjust.',
                    style: theme.bodySmall?.copyWith(
                      color: AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  resolving
                      ? Icons.sync_rounded
                      : Icons.place_rounded,
                  color: resolving ? AppColors.textFaint : AppColors.accent,
                  size: 19,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resolving
                          ? 'Finding the address…'
                          : address.isEmpty
                              ? 'Drag the map to place the pin'
                              : address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.bodySmall?.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${pinned.latitude.toStringAsFixed(5)}, '
                      '${pinned.longitude.toStringAsFixed(5)}',
                      style: theme.bodySmall?.copyWith(
                        color: AppColors.textFaint,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (cityEditable) ...[
          const SizedBox(height: 14),
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
          Row(
            children: [
              const Icon(
                Icons.location_city_rounded,
                color: AppColors.textFaint,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text('City: $city', style: theme.bodySmall),
            ],
          ),
        ],
      ],
    );
  }
}


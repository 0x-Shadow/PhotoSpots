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
import '../services/photo_compression.dart';
import '../services/photo_metadata.dart';
import '../state/app_state.dart';
import '../state/auth_state.dart';
import '../state/location_outcome.dart';
import '../state/settings_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/location_prompt.dart';
import '../widgets/map_pin.dart';
import '../widgets/spot_details_form.dart';
import 'auth_screen.dart';
import 'legal_screen.dart';

/// Streamlined 2-step spot composer:
///   1. Pick or capture a photo (EXIF GPS is read locally before compression).
///   2. Fine-tune the pin, add a title/tags, and publish in one tap.
class SubmitScreen extends StatefulWidget {
  const SubmitScreen({super.key, this.initialStep = 0});

  /// Optional entry step — tests use `initialStep: 1` to inspect the map/form.
  final int initialStep;

  static LatLng initialPin(AppState state, {LatLng? mapCenter}) {
    if (state.hasCachedFix) return state.referenceLocation;
    return mapCenter ?? AppState.fallbackCenter;
  }

  @override
  State<SubmitScreen> createState() => _SubmitScreenState();
}

class _SubmitScreenState extends State<SubmitScreen> {
  late int _step = widget.initialStep.clamp(0, 1);
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

  @override
  void initState() {
    super.initState();
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

  Future<void> _pickPhoto(ImageSource source) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      // Keep the original asset until GPS is read. Some platform pickers can
      // return a metadata-stripped preview unless full metadata is requested.
      final picked = await ImagePicker().pickImage(
        source: source,
        requestFullMetadata: true,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final gps = PhotoMetadata.readGps(bytes);
      if (!mounted) return;
      setState(() {
        _photoBytes = bytes;
        _photoLocation = gps;
        _step = 1;
      });
      if (gps != null) {
        _applyPhotoLocation(gps);
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Photo location detected — the pin uses where this photo was taken.',
            ),
          ),
        );
      }
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
      } catch (_) {}
    });
    _resolveAddress(point);
  }

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
      _usingDemoSeed = false;
      _cityManual = suggestion.city.isEmpty;
      _draft
        ..city = suggestion.city
        ..name = suggestion.label.split(',').first.trim();
    });
    try {
      _mapController.move(point, 15);
    } catch (_) {}
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
    } catch (_) {}
    _resolveAddress(point);
  }

  Future<void> _publish() async {
    if (_submitting || !_draft.canPublish) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final app = context.read<AppState>();
    setState(() => _submitting = true);

    try {
      // EXIF GPS was already extracted at pick time; compressForUpload strips
      // raw EXIF/XMP metadata before uploading to public storage.
      final photoBytes = _photoBytes == null
          ? null
          : await compressForUpload(_photoBytes!);
      await app.submitSpot(
        title: _draft.name.trim(),
        description: _draft.tip.trim().isEmpty
            ? 'A photo spot shared by the ${AppInfo.name} community.'
            : _draft.tip.trim(),
        location: _pinned,
        city: _draft.city.trim(),
        tags: _draft.tags.toList(),
        bestTime: _draft.bestTime,
        focalLength: _draft.focalLength,
        tripodFriendly: _draft.tripodFriendly,
        accessNote: _draft.accessNote.trim(),
        photoBytes: photoBytes,
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
    if (_step > 0 && widget.initialStep == 0) {
      setState(() => _step = 0);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();

    // Restrict publishing to real accounts when the backend is active.
    if (!auth.canContribute) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: const Text('Share a spot'),
        ),
        body: SafeArea(
          child: ResponsiveBody(
            maxWidth: 460,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/images/upload_hero.jpg',
                      width: 180,
                      height: 180,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Sign in to share spots',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Publishing is restricted to signed-in accounts so '
                    'contributors get credit and the map stays spam-free.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 24),
                  PressButton(
                    semanticLabel: 'Sign in or create account',
                    onTap: () =>
                        Navigator.of(context)
                            .push(AppMotion.slideUp(const AuthScreen())),
                    child: Container(
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.action,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Sign in or create account',
                        style: TextStyle(
                          color: AppColors.onAction,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: _step == 0 || widget.initialStep != 0,
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
          title: Text(_step == 0 ? 'New Spot' : 'Pin & Details'),
          centerTitle: true,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x14FFFFFF),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.hairline),
                  ),
                  child: Text(
                    'Step ${_step + 1} of 2',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: ResponsiveBody(
            maxWidth: 640,
            child: AnimatedSwitcher(
              duration: AppMotion.quick,
              child: _step == 0
                  ? _PhotoStudioStep(
                      key: const ValueKey('step-photo'),
                      photoBytes: _photoBytes,
                      photoLocation: _photoLocation,
                      onPick: _pickPhoto,
                      onContinue: _photoBytes == null
                          ? null
                          : () => setState(() => _step = 1),
                    )
                  : _PinAndDetailsStep(
                      key: const ValueKey('step-details'),
                      photoBytes: _photoBytes,
                      photoLocation: _photoLocation,
                      pinned: _pinned,
                      usingDemoSeed: _usingDemoSeed,
                      address: _address,
                      cityEditable: _cityManual,
                      suggestions: _suggestions,
                      searching: _searching,
                      searchFailed: _searchFailed,
                      searchEmpty: _searchEmpty,
                      resolving: _resolving,
                      submitting: _submitting,
                      streetFallback: _streetFallback,
                      draft: _draft,
                      mapController: _mapController,
                      searchController: _searchController,
                      onChangePhoto: () => setState(() => _step = 0),
                      onSearch: _search,
                      onChoose: _chooseSuggestion,
                      onCenterChanged: _onCenterChanged,
                      onTapPoint: (point) {
                        try {
                          _mapController.move(
                            point,
                            _mapController.camera.zoom,
                          );
                        } catch (_) {}
                      },
                      onMapReady: () => _mapReadyForPin = true,
                      onUseMyLocation: _useMyLocation,
                      onFallback: () {
                        if (!_streetFallback) {
                          setState(() => _streetFallback = true);
                        }
                      },
                      onPublish: _publish,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoStudioStep extends StatelessWidget {
  const _PhotoStudioStep({
    super.key,
    required this.photoBytes,
    required this.photoLocation,
    required this.onPick,
    required this.onContinue,
  });

  final Uint8List? photoBytes;
  final PhotoLocation? photoLocation;
  final ValueChanged<ImageSource> onPick;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final hasPhoto = photoBytes != null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        const Text(
          'Show the spot at its best',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 26,
            height: 1.12,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Pick a photo and we’ll read its GPS locally to place the pin, '
          'then strip personal metadata before upload.',
          style: theme.bodyMedium,
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: () => onPick(ImageSource.gallery),
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 310,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: hasPhoto
                    ? AppColors.accent.withValues(alpha: 0.45)
                    : const Color(0x26FFFFFF),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(23),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasPhoto)
                    Image.memory(
                      photoBytes!,
                      fit: BoxFit.cover,
                      cacheWidth: 1080,
                    )
                  else
                    Image.asset(
                      'assets/images/upload_hero.jpg',
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: AppColors.surfaceElevated),
                    ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x22000000),
                          Color(0x33000000),
                          Color(0xCC0A0A0B),
                        ],
                        stops: [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: 18,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasPhoto && photoLocation != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xB3000000),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: AppColors.success.withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.gps_fixed_rounded,
                                  color: AppColors.success,
                                  size: 13,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'GPS detected · $photoLocation',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (hasPhoto)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xB3000000),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: const Color(0x40FFFFFF)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.location_off_rounded,
                                  color: Color(0xCCFFFFFF),
                                  size: 13,
                                ),
                                SizedBox(width: 5),
                                Text(
                                  'No location in this photo — you\'ll place '
                                  'the pin next',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Text(
                          hasPhoto
                              ? 'Tap to swap photo'
                              : 'Tap to choose a photo',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'JPEG, PNG or HEIC · EXIF metadata stripped on upload',
                          style: TextStyle(
                            color: Color(0xCCFFFFFF),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _StudioButton(
                icon: Icons.photo_library_rounded,
                label: hasPhoto ? 'Choose another' : 'Gallery',
                filled: true,
                onTap: () => onPick(ImageSource.gallery),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StudioButton(
                icon: Icons.photo_camera_rounded,
                label: 'Camera',
                onTap: () => onPick(ImageSource.camera),
              ),
            ),
          ],
        ),
        if (onContinue != null) ...[
          const SizedBox(height: 12),
          PressButton(
            semanticLabel: 'Continue to pin and details',
            onTap: onContinue!,
            child: Container(
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'Continue to Pin & Details',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _StudioButton extends StatelessWidget {
  const _StudioButton({
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
    return PressButton(
      semanticLabel: label,
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: filled ? AppColors.action : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: filled ? AppColors.action : AppColors.hairline,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: filled ? AppColors.onAction : AppColors.textPrimary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: filled ? AppColors.onAction : AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinAndDetailsStep extends StatelessWidget {
  const _PinAndDetailsStep({
    super.key,
    required this.photoBytes,
    required this.photoLocation,
    required this.pinned,
    required this.usingDemoSeed,
    required this.address,
    required this.cityEditable,
    required this.suggestions,
    required this.searching,
    required this.searchFailed,
    required this.searchEmpty,
    required this.resolving,
    required this.submitting,
    required this.streetFallback,
    required this.draft,
    required this.mapController,
    required this.searchController,
    required this.onChangePhoto,
    required this.onSearch,
    required this.onChoose,
    required this.onCenterChanged,
    required this.onTapPoint,
    required this.onMapReady,
    required this.onUseMyLocation,
    required this.onFallback,
    required this.onPublish,
  });

  final Uint8List? photoBytes;
  final PhotoLocation? photoLocation;
  final LatLng pinned;
  final bool usingDemoSeed;
  final String address;
  final bool cityEditable;
  final List<PlaceSuggestion> suggestions;
  final bool searching;
  final bool searchFailed;
  final bool searchEmpty;
  final bool resolving;
  final bool submitting;
  final bool streetFallback;
  final SpotDraftController draft;
  final MapController mapController;
  final TextEditingController searchController;
  final VoidCallback onChangePhoto;
  final ValueChanged<String> onSearch;
  final ValueChanged<PlaceSuggestion> onChoose;
  final ValueChanged<LatLng> onCenterChanged;
  final ValueChanged<LatLng> onTapPoint;
  final VoidCallback onMapReady;
  final VoidCallback onUseMyLocation;
  final VoidCallback onFallback;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final style = streetFallback
        ? TileSources.street
        : context.watch<SettingsState>().activeMapStyle;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
      children: [
        if (photoBytes != null) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    photoBytes!,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    cacheWidth: 160,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Cover photo ready',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        photoLocation != null
                            ? 'Pinned from photo GPS · drag map to adjust'
                            : 'No photo GPS · drag map or search below',
                        style: theme.bodySmall?.copyWith(
                          color: photoLocation != null
                              ? AppColors.success
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: onChangePhoto,
                  child: const Text('Change'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
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
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
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
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.hairline),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: suggestions.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: AppColors.hairline),
              itemBuilder: (_, i) {
                final s = suggestions[i];
                return InkWell(
                  onTap: () => onChoose(s),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.place_outlined,
                          color: AppColors.accent,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            s.city.isNotEmpty
                                ? '${s.label} · ${s.city}'
                                : s.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        if (searchFailed || searchEmpty) ...[
          const SizedBox(height: 8),
          Text(
            searchFailed
                ? 'Search is unavailable right now. Drag the map to place the pin.'
                : 'No places found. Drag the map to place the pin.',
            style: theme.bodySmall,
          ),
        ],
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(
            height: 250,
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
                        flags:
                            InteractiveFlag.drag |
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
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xF20F0F11),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0x33FFFFFF)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.my_location_rounded,
                            color: AppColors.textPrimary,
                            size: 15,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'My location',
                            style: theme.labelLarge?.copyWith(
                              color: AppColors.textPrimary,
                              fontSize: 12.5,
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
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              Icon(
                resolving ? Icons.sync_rounded : Icons.place_rounded,
                color: resolving ? AppColors.textFaint : AppColors.accent,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  resolving
                      ? 'Finding the address…'
                      : address.isEmpty
                      ? '${pinned.latitude.toStringAsFixed(5)}, '
                            '${pinned.longitude.toStringAsFixed(5)}'
                      : address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodySmall?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SpotDetailsForm(
          controller: draft,
          initialName: draft.name,
          initialCity: draft.city,
          cityEditable: cityEditable,
          submitting: submitting,
          onPublish: onPublish,
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              AppMotion.slideUp(const LegalScreen(doc: LegalDoc.guidelines)),
            ),
            child: const Text(
              'By publishing you agree to our Community Guidelines',
              style: TextStyle(color: AppColors.textFaint, fontSize: 11.5),
            ),
          ),
        ),
      ],
    );
  }
}

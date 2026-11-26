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
import '../state/app_state.dart';
import '../state/location_outcome.dart';
import '../state/settings_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/location_prompt.dart';

/// A deliberately short publishing flow: choose the shot, then add just
/// enough context to make it useful.
class SubmitScreen extends StatefulWidget {
  const SubmitScreen({super.key});

  @override
  State<SubmitScreen> createState() => _SubmitScreenState();
}

class _SubmitScreenState extends State<SubmitScreen> {
  int _step = 0;

  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _cityController = TextEditingController(text: 'Lisbon');

  String? _bestTime;
  final Set<String> _tags = {};
  LatLng _pinned = AppState.fallbackCenter;
  Uint8List? _photoBytes;
  bool _submitting = false;

  static const _stepTitles = ['Choose photo', 'Share the spot'];

  static const _tagOptions = [
    'skyline',
    'sunset',
    'date',
    'friends',
    'street',
    'architecture',
    'water',
    'nightlife',
    'hidden gem',
    'reflection',
  ];

  static const _bestTimeOptions = [
    'Golden hour',
    'Blue hour',
    'Morning light',
    'Night',
    'Afternoon',
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<AppState>();
      _pinned = state.referenceLocation;
      if (!state.hasUserLocation) {
        state.requestLocation().then((outcome) {
          if (mounted && outcome == LocationOutcome.granted) {
            setState(
              () => _pinned = context.read<AppState>().referenceLocation,
            );
          }
        });
      }
    });
  }

  bool get _canProceed {
    switch (_step) {
      case 0:
        return _photoBytes != null;
      case 1:
        return _titleController.text.trim().isNotEmpty &&
            _cityController.text.trim().isNotEmpty;
      default:
        return true;
    }
  }

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

  Future<void> _next() async {
    if (_step == 1) {
      await _publish();
      return;
    }
    if (!_canProceed) return;
    setState(() => _step++);
  }

  Future<void> _publish() async {
    if (_submitting) return;
    if (!_canProceed) {
      setState(() => _step = 0);
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _submitting = true);

    try {
      await context.read<AppState>().submitSpot(
        title: _titleController.text.trim(),
        description: _descController.text.trim().isEmpty
            ? 'A photo spot shared by the findr community.'
            : _descController.text.trim(),
        location: _pinned,
        city: _cityController.text.trim(),
        tags: _tags.toList(),
        bestTime: _bestTime,
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
        if (!didPop) setState(() => _step--);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: PressButton(
            semanticLabel: _step == 0 ? 'Close' : 'Back',
            onTap: _back,
            child: Container(
              width: 40,
              height: 40,
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
                Expanded(child: _stepContent()),
                _BottomBar(
                  step: _step,
                  enabled: _canProceed && !_submitting,
                  submitting: _submitting,
                  onBack: _back,
                  onNext: _next,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepContent() {
    switch (_step) {
      case 0:
        return _PhotoStep(
          photoBytes: _photoBytes,
          onPick: _pickPhoto,
          onClear: () => setState(() => _photoBytes = null),
        );
      case 1:
        return _DetailsStep(
          titleController: _titleController,
          descController: _descController,
          cityController: _cityController,
          bestTime: _bestTime,
          tags: _tags,
          bestTimeOptions: _bestTimeOptions,
          tagOptions: _tagOptions,
          onChanged: () => setState(() {}),
          onBestTimeChanged: (value) => setState(() => _bestTime = value),
          onTagsChanged: (value) => setState(() {
            _tags
              ..clear()
              ..addAll(value);
          }),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.step, required this.titles});

  final int step;
  final List<String> titles;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        children: [
          Row(
            children: [
              for (var i = 0; i < titles.length; i++)
                Expanded(
                  child: Container(
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i <= step
                          ? AppColors.action
                          : const Color(0x1AFFFFFF),
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
                    style: TextStyle(
                      color: i <= step
                          ? AppColors.textPrimary
                          : AppColors.textFaint,
                      fontSize: 10.5,
                      fontWeight: i <= step ? FontWeight.w700 : FontWeight.w500,
                      fontFamily: 'Inter',
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
    required this.submitting,
    required this.onBack,
    required this.onNext,
  });

  final int step;
  final bool enabled;
  final bool submitting;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (step > 0) ...[
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: submitting ? null : onBack,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.hairline),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Back',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              flex: step > 0 ? 2 : 1,
              child: PressButton(
                semanticLabel: step == 1 ? 'Publish spot' : 'Next step',
                enabled: enabled,
                onTap: onNext,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: enabled ? AppColors.action : const Color(0x1AFFFFFF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onAction,
                          ),
                        )
                      : Text(
                          step == 1 ? 'Publish spot' : 'Next',
                          style: TextStyle(
                            color: enabled
                                ? AppColors.onAction
                                : AppColors.textFaint,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Inter',
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      children: [
        const Text(
          'Show the spot at its best',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'One photo is required. Pick your best shot — it becomes the cover.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.45,
            fontFamily: 'Inter',
          ),
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
                      const Icon(
                        Icons.add_a_photo_rounded,
                        color: AppColors.textSecondary,
                        size: 42,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Add your best shot',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Inter',
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'JPG or PNG · one photo required',
                        style: TextStyle(
                          color: AppColors.textFaint,
                          fontSize: 12,
                          fontFamily: 'Inter',
                        ),
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
                              child: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 19,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Tap to change',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontFamily: 'Inter',
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
          style: TextStyle(
            color: photoBytes == null ? AppColors.textFaint : AppColors.success,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
          ),
        ),
      ],
    );
  }
}

/// Small pill used on the photo step to pick gallery or camera.
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
            Icon(
              icon,
              size: 17,
              color: filled ? AppColors.onAction : AppColors.textPrimary,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: filled ? AppColors.onAction : AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailsStep extends StatefulWidget {
  const _DetailsStep({
    required this.titleController,
    required this.descController,
    required this.cityController,
    required this.bestTime,
    required this.tags,
    required this.bestTimeOptions,
    required this.tagOptions,
    required this.onChanged,
    required this.onBestTimeChanged,
    required this.onTagsChanged,
  });

  final TextEditingController titleController;
  final TextEditingController descController;
  final TextEditingController cityController;
  final String? bestTime;
  final Set<String> tags;
  final List<String> bestTimeOptions;
  final List<String> tagOptions;
  final VoidCallback onChanged;
  final ValueChanged<String?> onBestTimeChanged;
  final ValueChanged<Set<String>> onTagsChanged;

  @override
  State<_DetailsStep> createState() => _DetailsStepState();
}

class _DetailsStepState extends State<_DetailsStep> {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        const _FieldLabel('Spot name'),
        const SizedBox(height: 8),
        TextFormField(
          controller: widget.titleController,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => widget.onChanged(),
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Miradouro da Senhora do Monte',
          ),
        ),
        const SizedBox(height: 18),
        const _FieldLabel('A tip for visitors (optional)'),
        const SizedBox(height: 8),
        TextFormField(
          controller: widget.descController,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => widget.onChanged(),
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Where to stand, when to go, what lens…',
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.descController.text.trim().isEmpty
              ? 'A short note helps others find the exact angle.'
              : 'Nice — that gives people useful context.',
          style: const TextStyle(
            color: AppColors.textFaint,
            fontSize: 11.5,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 18),
        const _FieldLabel('City'),
        const SizedBox(height: 8),
        TextFormField(
          controller: widget.cityController,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => widget.onChanged(),
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: 'Lisbon'),
        ),
        const SizedBox(height: 22),
        const _FieldLabel('Best time to shoot'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in widget.bestTimeOptions)
              _TagChip(
                label: option,
                selected: widget.bestTime == option,
                onTap: () => widget.onBestTimeChanged(
                  widget.bestTime == option ? null : option,
                ),
              ),
          ],
        ),
        const SizedBox(height: 22),
        const _FieldLabel('Tags'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in widget.tagOptions)
              _TagChip(
                label: '#$tag',
                selected: widget.tags.contains(tag),
                onTap: () {
                  final next = Set<String>.from(widget.tags);
                  if (!next.remove(tag)) next.add(tag);
                  widget.onTagsChanged(next);
                },
              ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        fontFamily: 'Inter',
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: AppMotion.instant,
        constraints: const BoxConstraints(minHeight: 38),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.action : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.action : AppColors.hairline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.onAction : AppColors.textSecondary,
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            fontFamily: 'Inter',
          ),
        ),
      ),
    );
  }
}

class _LocationStep extends StatefulWidget {
  const _LocationStep({required this.pinned, required this.onPinMoved});

  final LatLng pinned;
  final ValueChanged<LatLng> onPinMoved;

  @override
  State<_LocationStep> createState() => _LocationStepState();
}

class _LocationStepState extends State<_LocationStep> {
  final _mapController = MapController();
  late LatLng _center;

  /// Set once the preferred basemap turns out to be unusable, so this
  /// mini-map swaps to the street style for the rest of the session.
  bool _streetFallback = false;

  @override
  void initState() {
    super.initState();
    _center = widget.pinned;
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _useMyLocation() async {
    final state = context.read<AppState>();
    final outcome = await runLocationFlow(context);
    if (!mounted) return;

    if (outcome != LocationOutcome.granted || state.userLocation == null) {
      return;
    }

    final point = LatLng(
      state.userLocation!.latitude,
      state.userLocation!.longitude,
    );
    _mapController.move(point, 16);
    setState(() => _center = point);
    widget.onPinMoved(point);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        const Text(
          'Drag the map so the pin sits on the spot',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 14),
        Container(
          height: 320,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _center,
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
                  onPositionChanged: (camera, _) {
                    final next = camera.center;
                    if ((next.latitude - _center.latitude).abs() > 1e-6 ||
                        (next.longitude - _center.longitude).abs() > 1e-6) {
                      setState(() => _center = next);
                      widget.onPinMoved(next);
                    }
                  },
                ),
                children: [
                  MapTileLayers(
                    style: _streetFallback
                        ? TileSources.street
                        : context.watch<SettingsState>().activeMapStyle,
                    onFallback: (id) {
                      if (_streetFallback) return;
                      setState(() => _streetFallback = true);
                    },
                  ),
                  MapAttribution(
                    style: _streetFallback
                        ? TileSources.street
                        : context.watch<SettingsState>().activeMapStyle,
                  ),
                ],
              ),
              IgnorePointer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: const BoxDecoration(
                        color: AppColors.action,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.photo_camera_rounded,
                        color: AppColors.onAction,
                        size: 21,
                      ),
                    ),
                    const Icon(
                      Icons.arrow_drop_down_rounded,
                      color: AppColors.textPrimary,
                      size: 28,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Pin set on the map',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                  fontFamily: 'Inter',
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _useMyLocation,
              icon: const Icon(Icons.my_location_rounded, size: 16),
              label: const Text('Use my location'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                textStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        Text(
          '${_center.latitude.toStringAsFixed(5)}, '
          '${_center.longitude.toStringAsFixed(5)}',
          style: const TextStyle(
            color: AppColors.textFaint,
            fontSize: 11.5,
            fontFamily: 'Inter',
          ),
        ),
      ],
    );
  }
}

// Kept as a ready-to-reuse preview surface for a future edit flow.
// ignore: unused_element
class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    required this.photoBytes,
    required this.title,
    required this.description,
    required this.city,
    required this.bestTime,
    required this.tags,
    required this.latitude,
    required this.longitude,
  });

  final Uint8List? photoBytes;
  final String title;
  final String description;
  final String city;
  final String? bestTime;
  final List<String> tags;
  final double latitude;
  final double longitude;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: 220,
            color: AppColors.surfaceElevated,
            child: photoBytes != null
                ? Image.memory(photoBytes!, fit: BoxFit.cover)
                : const Center(
                    child: Icon(
                      Icons.landscape_rounded,
                      color: AppColors.textFaint,
                      size: 40,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 21,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Icon(
              Icons.place_rounded,
              color: AppColors.textSecondary,
              size: 14,
            ),
            const SizedBox(width: 4),
            Text(
              city,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(width: 12),
            const Icon(
              Icons.near_me_rounded,
              color: AppColors.textFaint,
              size: 13,
            ),
            const SizedBox(width: 4),
            Text(
              '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}',
              style: const TextStyle(
                color: AppColors.textFaint,
                fontSize: 11.5,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          description,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.55,
            fontFamily: 'Inter',
          ),
        ),
        if (bestTime != null) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(
                Icons.wb_sunny_outlined,
                color: AppColors.catSunset,
                size: 15,
              ),
              const SizedBox(width: 6),
              Text(
                'Best shot: $bestTime',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ],
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final tag in tags)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.hairline),
                  ),
                  child: Text(
                    '#$tag',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 18),
        Text(
          AppInfo.backendConfigured
              ? 'Your spot will appear on the map for everyone to discover.'
              : 'Demo mode: this spot is kept in memory and resets when the app '
                    'closes, because no backend is configured.',
          style: const TextStyle(
            color: AppColors.textFaint,
            fontSize: 12,
            height: 1.45,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 6),
        Text(
          AppInfo.backendConfigured
              ? 'The photo is uploaded with the spot.'
              : 'The photo is not uploaded anywhere in demo mode.',
          style: const TextStyle(
            color: AppColors.textFaint,
            fontSize: 11.5,
            fontFamily: 'Inter',
          ),
        ),
      ],
    );
  }
}

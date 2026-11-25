import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../data/supabase_repository.dart';
import '../state/app_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';

/// Submit flow — step-by-step upload page styled like the reference.
class SubmitScreen extends StatefulWidget {
  const SubmitScreen({super.key});

  @override
  State<SubmitScreen> createState() => _SubmitScreenState();
}

class _SubmitScreenState extends State<SubmitScreen> {
  int _step = 0; // 0: photo, 1: details, 2: location, 3: review/publish

  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _cityController = TextEditingController(text: 'Lisbon');

  String? _bestTime;
  Set<String> _tags = {};
  LatLng _pinned = const LatLng(38.7128, -9.1393);
  bool _submitting = false;
  XFile? _photoFile;

  static const _tagOptions = [
    'skyline',
    'sunset',
    'street',
    'architecture',
    'water',
    'nightlife',
    'hidden gem',
    'reflection',
    'tiles',
    'landmark',
  ];
  static const _bestTimeOptions = [
    'Golden hour',
    'Blue hour',
    'Morning light',
    'Night',
    'Afternoon',
  ];

  static const _stepTitles = [
    'Add a photo',
    'Tell us about it',
    'Drop the pin',
    'Review',
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked != null && mounted) {
      setState(() => _photoFile = picked);
    }
  }

  bool get _canProceed {
    switch (_step) {
      case 0:
        return _photoFile != null;
      case 1:
        return _titleController.text.trim().isNotEmpty &&
            _descController.text.trim().length >= 10;
      case 2:
        return true;
      case 3:
        return true;
      default:
        return false;
    }
  }

  Future<void> _next() async {
    if (_step == 3) {
      await _publish();
      return;
    }
    if (!_canProceed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete this step first')),
      );
      return;
    }
    setState(() => _step++);
  }

  Future<void> _back() async {
    if (_step > 0 && mounted) {
      setState(() => _step--);
    }
  }

  Future<void> _publish() async {
    setState(() => _submitting = true);
    try {
      final state = context.read<AppState>();
      await state.submitSpot(
        title: _titleController.text.trim(),
        description: _descController.text.trim(),
        location: _pinned,
        city: _cityController.text.trim(),
        tags: _tags.toList(),
        bestTime: _bestTime,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Spot added to the map 📍')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: PressButton(
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0x1AFFFFFF),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.hairline),
            ),
            child: const Icon(Icons.arrow_back_rounded,
                color: AppColors.textPrimary, size: 22),
          ),
          onTap: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _stepTitles[_step],
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            fontFamily: 'Inter',
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Progress bar.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (int i = 0; i < 4; i++) ...[
                        Expanded(
                          child: Container(
                            height: 4,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: i <= _step
                                  ? AppColors.action
                                  : const Color(0x1AFFFFFF),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (int i = 0; i < 4; i++) ...[
                        Expanded(
                          child: Text(
                            _stepTitles[i],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: i <= _step
                                  ? AppColors.textPrimary
                                  : AppColors.textFaint,
                              fontSize: 11,
                              fontWeight: i <= _step
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            Expanded(
              child: _stepContent(),
            ),

            // Bottom nav.
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border(
                  top: BorderSide(color: AppColors.hairline),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    if (_step > 0)
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: OutlinedButton(
                            onPressed: _back,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textPrimary,
                              side: const BorderSide(color: AppColors.hairline),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: const Text('Back',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'Inter')),
                          ),
                        ),
                      ),
                    if (_step > 0) const SizedBox(width: 12),
                    Expanded(
                      flex: _step > 0 ? 2 : 1,
                      child: SizedBox(
                        height: 52,
                        child: PressButton(
                          child: Container(
                            decoration: BoxDecoration(
                              color: _canProceed
                                  ? AppColors.action
                                  : const Color(0x1AFFFFFF),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _step == 3 ? 'Publish' : 'Next',
                              style: const TextStyle(
                                color: AppColors.onAction,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                fontFamily: 'Inter',
                              ),
                            ),
                          ),
                          onTap: _next,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepContent() {
    switch (_step) {
      case 0:
        return _PhotoStep();
      case 1:
        return _DetailsStep(
          titleController: _titleController,
          descController: _descController,
          cityController: _cityController,
          bestTime: _bestTime,
          tags: _tags,
          onBestTimeChanged: (v) => setState(() => _bestTime = v),
          onTagsChanged: (t) => setState(() => _tags = t),
        );
      case 2:
        return _LocationStep(
          pinned: _pinned,
          onPinMoved: (p) => setState(() => _pinned = p),
        );
      case 3:
        return _ReviewStep(
          title: _titleController.text.trim(),
          description: _descController.text.trim(),
          city: _cityController.text.trim(),
          bestTime: _bestTime,
          tags: _tags,
          photoFile: _photoFile,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ================= STEP 0: PHOTO =================

class _PhotoStep extends StatefulWidget {
  @override
  State<_PhotoStep> createState() => _PhotoStepState();
}

class _PhotoStepState extends State<_PhotoStep> {
  XFile? _photoFile;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 24),
        const Text(
          'Add a photo',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Pick your best shot of the spot',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () async {
            final picker = ImagePicker();
            final picked = await picker.pickImage(
              source: ImageSource.gallery,
              maxWidth: 1600,
              imageQuality: 85,
            );
            if (picked != null && mounted) {
              setState(() => _photoFile = picked);
            }
          },
          child: Container(
            width: double.infinity,
            height: 260,
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.hairline),
            ),
            child: _photoFile == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_a_photo_rounded,
                          color: AppColors.textSecondary, size: 48),
                      const SizedBox(height: 12),
                      const Text(
                        'Add a photo of the spot',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.file(
                          File(_photoFile!.path),
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: GestureDetector(
                          onTap: () => setState(() => _photoFile = null),
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 16),
        if (_photoFile == null)
          Text(
            'A photo is required to continue',
            style: const TextStyle(
              color: AppColors.danger,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              fontFamily: 'Inter',
            ),
          ),
      ],
    );
  }
}

// ================= STEP 1: DETAILS =================

class _DetailsStep extends StatefulWidget {
  final TextEditingController titleController;
  final TextEditingController descController;
  final TextEditingController cityController;
  final String? bestTime;
  final Set<String> tags;
  final Function(String?) onBestTimeChanged;
  final Function(Set<String>) onTagsChanged;

  const _DetailsStep({
    required this.titleController,
    required this.descController,
    required this.cityController,
    required this.bestTime,
    required this.tags,
    required this.onBestTimeChanged,
    required this.onTagsChanged,
  });

  static const _tagOptions = [
    'skyline',
    'sunset',
    'street',
    'architecture',
    'water',
    'nightlife',
    'hidden gem',
    'reflection',
    'tiles',
    'landmark',
  ];
  static const _bestTimeOptions = [
    'Golden hour',
    'Blue hour',
    'Morning light',
    'Night',
    'Afternoon',
  ];

  @override
  State<_DetailsStep> createState() => _DetailsStepState();
}

class _DetailsStepState extends State<_DetailsStep> {
  late String? _bestTime;
  late Set<String> _tags;

  @override
  void initState() {
    super.initState();
    _bestTime = widget.bestTime;
    _tags = Set.from(widget.tags);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        const SizedBox(height: 8),
        _FieldLabel('Spot name'),
        const SizedBox(height: 8),
        TextFormField(
          controller: widget.titleController,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Miradouro da Senhora do Monte',
            hintStyle: TextStyle(color: AppColors.textFaint),
          ),
        ),
        const SizedBox(height: 20),
        _FieldLabel('What makes it special?'),
        const SizedBox(height: 8),
        TextFormField(
          controller: widget.descController,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Where to stand, when to go, what lens…',
            hintStyle: TextStyle(color: AppColors.textFaint),
          ),
        ),
        const SizedBox(height: 20),
        _FieldLabel('City'),
        const SizedBox(height: 8),
        TextFormField(
          controller: widget.cityController,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Lisbon',
            hintStyle: TextStyle(color: AppColors.textFaint),
          ),
        ),
        const SizedBox(height: 24),
        _FieldLabel('Best time to shoot'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in _DetailsStep._bestTimeOptions)
              _TagChip(
                label: t,
                selected: _bestTime == t,
                onTap: () => setState(() {
                  _bestTime = _bestTime == t ? null : t;
                  widget.onBestTimeChanged(_bestTime);
                }),
              ),
          ],
        ),
        const SizedBox(height: 24),
        _FieldLabel('Tags'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in _DetailsStep._tagOptions)
              _TagChip(
                label: '#$t',
                selected: _tags.contains(t),
                onTap: () {
                  setState(() {
                    _tags.contains(t) ? _tags.remove(t) : _tags.add(t);
                  });
                  widget.onTagsChanged(Set.from(_tags));
                },
              ),
          ],
        ),
        const SizedBox(height: 40),
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
        fontSize: 14,
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.action : const Color(0x1AFFFFFF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.action : AppColors.hairline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.onAction : AppColors.textSecondary,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            fontFamily: 'Inter',
          ),
        ),
      ),
    );
  }
}

// ================= STEP 2: LOCATION =================

class _LocationStep extends StatefulWidget {
  final LatLng pinned;
  final Function(LatLng) onPinMoved;

  const _LocationStep({required this.pinned, required this.onPinMoved});

  @override
  State<_LocationStep> createState() => _LocationStepState();
}

class _LocationStepState extends State<_LocationStep> {
  late LatLng _pinned;

  @override
  void initState() {
    super.initState();
    _pinned = widget.pinned;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 24),
        const Text(
          'Drop the pin',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Drag the map so the marker sits on your spot',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 16),
        Container(
          height: 300,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.hairline),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              alignment: Alignment.center,
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: _pinned,
                    initialZoom: 13,
                    backgroundColor: AppColors.mapBackground,
                    // NO rotation — drag and zoom only.
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.drag |
                          InteractiveFlag.pinchZoom |
                          InteractiveFlag.doubleTapZoom |
                          InteractiveFlag.flingAnimation,
                    ),
                    onPositionChanged: (camera, _) {
                      final c = camera.center;
                      if ((c.latitude - _pinned.latitude).abs() > 1e-5 ||
                          (c.longitude - _pinned.longitude).abs() > 1e-5) {
                        setState(() => _pinned = c);
                        widget.onPinMoved(c);
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.photospot.app',
                    ),
                  ],
                ),
                IgnorePointer(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: AppColors.textPrimary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black54,
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.photo_camera_rounded,
                            color: AppColors.onAction, size: 22),
                      ),
                      const Icon(Icons.arrow_drop_down_rounded,
                          color: AppColors.textPrimary, size: 30),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Pin set on the map',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            fontFamily: 'Inter',
          ),
        ),
      ],
    );
  }
}

// ================= STEP 3: REVIEW =================

class _ReviewStep extends StatelessWidget {
  final String title;
  final String description;
  final String city;
  final String? bestTime;
  final Set<String> tags;
  final XFile? photoFile;

  const _ReviewStep({
    required this.title,
    required this.description,
    required this.city,
    required this.bestTime,
    required this.tags,
    required this.photoFile,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 24),
        const Text(
          'Review before publishing',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Your spot will appear on the map for everyone to discover',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          height: 200,
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.hairline),
          ),
          child: photoFile != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.file(
                    File(photoFile!.path),
                    fit: BoxFit.cover,
                  ),
                )
              : const Center(
                  child: Icon(Icons.landscape_rounded,
                      color: AppColors.textFaint, size: 44)),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title.isNotEmpty) ...[
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.place_rounded,
                        color: AppColors.textSecondary, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      city,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const Spacer(),
                    if (tags.isNotEmpty)
                      Text(
                        '${tags.length} tags',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          fontFamily: 'Inter',
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13.5,
                    height: 1.5,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
              if (bestTime != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wb_sunny_outlined,
                          color: AppColors.catSunset, size: 15),
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
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

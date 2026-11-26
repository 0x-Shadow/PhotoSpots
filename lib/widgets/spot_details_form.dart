import 'package:flutter/material.dart';

import '../theme/app_animations.dart';
import '../theme/app_theme.dart';

/// Mutable draft shared by the Details step and the confirmation sheet.
class SpotDraftController {
  String name = '';
  String city = '';
  String tip = '';
  String? bestTime;
  final Set<String> tags = {};

  bool submitted = false;

  bool get canPublish => name.trim().isNotEmpty;
}

/// The last step of publishing: a name is the only required field. City is
/// derived from the pin and shown read-only unless geocoding failed.
class SpotDetailsForm extends StatefulWidget {
  const SpotDetailsForm({
    super.key,
    required this.controller,
    required this.initialName,
    required this.initialCity,
    this.onPublish,
    this.cityEditable = false,
  });

  final SpotDraftController controller;
  final String initialName;
  final String initialCity;
  final VoidCallback? onPublish;

  /// True only when the geocoder failed and the user must supply a city.
  final bool cityEditable;

  static const bestTimeOptions = [
    'Golden hour',
    'Blue hour',
    'Morning light',
    'Night',
    'Afternoon',
  ];

  static const tagOptions = [
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

  @override
  State<SpotDetailsForm> createState() => _SpotDetailsFormState();
}

class _SpotDetailsFormState extends State<SpotDetailsForm> {
  late final TextEditingController _name;
  late final TextEditingController _tip;
  late final TextEditingController _city;

  @override
  void initState() {
    super.initState();
    final draft = widget.controller;
    draft
      ..name = widget.initialName
      ..city = widget.initialCity;
    _name = TextEditingController(text: widget.initialName);
    _tip = TextEditingController(text: draft.tip);
    _city = TextEditingController(text: widget.initialCity);
  }

  @override
  void dispose() {
    _name.dispose();
    _tip.dispose();
    _city.dispose();
    super.dispose();
  }

  void _publish() {
    setState(() => widget.controller.submitted = true);
    if (!widget.controller.canPublish) return;
    widget.onPublish?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final draft = widget.controller;
    final showError = draft.submitted && !draft.canPublish;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        _FieldLabel('Spot name'),
        const SizedBox(height: 8),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          onChanged: (value) => setState(() => draft.name = value),
          style: theme.bodyLarge?.copyWith(color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: 'Name this place'),
        ),
        if (showError) ...[
          const SizedBox(height: 8),
          Text(
            'Give the spot a name to publish.',
            style: theme.bodySmall?.copyWith(color: AppColors.danger),
          ),
        ],
        const SizedBox(height: 18),
        _FieldLabel('A tip for visitors (optional)'),
        const SizedBox(height: 8),
        TextField(
          controller: _tip,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (value) => setState(() => draft.tip = value),
          style: theme.bodyLarge?.copyWith(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Where to stand, when to go, what lens…',
          ),
        ),
        const SizedBox(height: 18),
        _FieldLabel(widget.cityEditable ? 'City (enter manually)' : 'City'),
        const SizedBox(height: 8),
        TextField(
          controller: _city,
          enabled: widget.cityEditable,
          textCapitalization: TextCapitalization.words,
          onChanged: (value) => setState(() => draft.city = value),
          style: theme.bodyLarge?.copyWith(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'From the pin',
            suffixIcon: widget.cityEditable
                ? const Icon(Icons.edit_rounded,
                    color: AppColors.textFaint, size: 18)
                : null,
          ),
        ),
        if (!widget.cityEditable) ...[
          const SizedBox(height: 6),
          Text(
            'Filled in from the pin — change it under Location if needed.',
            style: theme.bodySmall,
          ),
        ],
        const SizedBox(height: 22),
        _FieldLabel('Best time to shoot'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in SpotDetailsForm.bestTimeOptions)
              _TagChip(
                label: option,
                selected: draft.bestTime == option,
                onTap: () => setState(() {
                  draft.bestTime = draft.bestTime == option ? null : option;
                }),
              ),
          ],
        ),
        const SizedBox(height: 22),
        _FieldLabel('Tags'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in SpotDetailsForm.tagOptions)
              _TagChip(
                label: '#$tag',
                selected: draft.tags.contains(tag),
                onTap: () => setState(() {
                  if (!draft.tags.remove(tag)) draft.tags.add(tag);
                }),
              ),
          ],
        ),
        const SizedBox(height: 24),
        PressButton(
          key: const ValueKey('details_publish'),
          semanticLabel: 'Publish spot',
          onTap: _publish,
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.action,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'Publish',
              style: theme.labelLarge?.copyWith(
                color: AppColors.onAction,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
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
      style: Theme.of(context).textTheme.titleSmall,
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
    final theme = Theme.of(context).textTheme;
    return PressButton(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.instant,
        constraints: const BoxConstraints(minHeight: 44),
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
          style: theme.labelLarge?.copyWith(
            color: selected ? AppColors.onAction : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

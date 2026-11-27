import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/spot.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/spot_details_form.dart';

/// Opens a modal sheet allowing a spot's owner to edit its title, tip, city,
/// shooting window, tags, and gear/access notes.
Future<bool> showEditSpotSheet(BuildContext context, Spot spot) async {
  final res = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _EditSpotSheet(spot: spot),
  );
  return res == true;
}

class _EditSpotSheet extends StatefulWidget {
  const _EditSpotSheet({required this.spot});

  final Spot spot;

  @override
  State<_EditSpotSheet> createState() => _EditSpotSheetState();
}

class _EditSpotSheetState extends State<_EditSpotSheet> {
  late final SpotDraftController _draft = SpotDraftController()
    ..name = widget.spot.title
    ..city = widget.spot.city
    ..tip = widget.spot.description
    ..bestTime = widget.spot.bestTime
    ..focalLength = widget.spot.focalLength
    ..tripodFriendly = widget.spot.tripodFriendly
    ..accessNote = widget.spot.accessNote ?? ''
    ..tags.addAll(widget.spot.tags);

  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (_saving || !_draft.canPublish) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<AppState>().updateSpot(
            spotId: widget.spot.id,
            title: _draft.name.trim(),
            description: _draft.tip.trim(),
            city: _draft.city.trim(),
            tags: _draft.tags.toList(),
            bestTime: _draft.bestTime,
            focalLength: _draft.focalLength,
            tripodFriendly: _draft.tripodFriendly,
            accessNote: _draft.accessNote.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save changes. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Edit spot',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 12.5),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: SpotDetailsForm(
                  controller: _draft,
                  initialName: widget.spot.title,
                  initialCity: widget.spot.city,
                  submitting: _saving,
                  publishLabel: 'Save changes',
                  onPublish: _save,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

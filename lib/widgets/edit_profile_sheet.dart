import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../screens/auth_screen.dart';
import '../state/auth_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import '../utils/validators.dart';

/// Opens the profile editor modal from Profile or Settings.
Future<bool> showEditProfileSheet(BuildContext context) async {
  final auth = context.read<AuthState>();
  final messenger = ScaffoldMessenger.of(context);
  if (AuthState.supportsAccounts && auth.isGuest) {
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign in to edit profile'),
        content: const Text(
          'Create an account or sign in so your display name, bio, city, and '
          'avatar are saved to your profile.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
    if (go == true && context.mounted) {
      await Navigator.of(context).push(AppMotion.slideUp(const AuthScreen()));
    }
    return false;
  }

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _EditProfileSheet(auth: auth),
  );
  if (result == true && context.mounted) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Profile updated.')),
    );
    return true;
  }
  return false;
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({required this.auth});

  final AuthState auth;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final _name = TextEditingController(text: widget.auth.displayName);
  late final _bio = TextEditingController(text: widget.auth.bio);
  late final _city = TextEditingController(text: widget.auth.city);
  Uint8List? _pickedAvatar;
  bool _removeAvatar = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 640,
        maxHeight: 640,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pickedAvatar = bytes;
        _removeAvatar = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not open the photo picker.');
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final nameErr = Validators.displayName(_name.text);
    if (nameErr != null) {
      setState(() => _error = nameErr);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await widget.auth.updateProfile(
      name: _name.text,
      bio: _bio.text,
      city: _city.text,
      avatarBytes: _pickedAvatar,
      removeAvatar: _removeAvatar,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!result.success) {
      setState(() => _error = result.message);
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final hasAvatar = !_removeAvatar &&
        (_pickedAvatar != null ||
            widget.auth.localAvatarBytes != null ||
            (widget.auth.avatarUrl?.isNotEmpty ?? false));

    Widget avatarPreview;
    if (!_removeAvatar && _pickedAvatar != null) {
      avatarPreview = Image.memory(_pickedAvatar!, fit: BoxFit.cover);
    } else if (!_removeAvatar && widget.auth.localAvatarBytes != null) {
      avatarPreview = Image.memory(
        widget.auth.localAvatarBytes!,
        fit: BoxFit.cover,
      );
    } else if (!_removeAvatar && (widget.auth.avatarUrl?.isNotEmpty ?? false)) {
      avatarPreview = Image.network(
        widget.auth.avatarUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Center(
          child: Text(
            widget.auth.initials,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    } else {
      avatarPreview = Center(
        child: Text(
          widget.auth.initials,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Edit profile',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.hairline, width: 1.5),
                  ),
                  child: ClipOval(child: avatarPreview),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _pickAvatar,
                        icon: const Icon(Icons.photo_camera_outlined, size: 16),
                        label: Text(hasAvatar ? 'Change photo' : 'Add photo'),
                      ),
                      if (hasAvatar)
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => setState(() {
                                    _pickedAvatar = null;
                                    _removeAvatar = true;
                                  }),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.danger,
                          ),
                          child: const Text('Remove'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('profile_name'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              maxLength: 32,
              decoration: const InputDecoration(
                labelText: 'Display name',
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('profile_bio'),
              controller: _bio,
              maxLines: 2,
              maxLength: 140,
              decoration: const InputDecoration(
                labelText: 'Bio',
                hintText: 'What do you like shooting?',
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('profile_city'),
              controller: _city,
              textCapitalization: TextCapitalization.words,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Home city',
                counterText: '',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: 12.5,
                ),
              ),
            ],
            const SizedBox(height: 18),
            PressButton(
              semanticLabel: 'Save profile',
              enabled: !_saving,
              onTap: _save,
              child: Container(
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.action,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onAction,
                        ),
                      )
                    : const Text(
                        'Save',
                        style: TextStyle(
                          color: AppColors.onAction,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
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

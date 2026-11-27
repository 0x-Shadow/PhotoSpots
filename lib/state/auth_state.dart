import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../app_info.dart';
import '../services/photo_compression.dart';
import '../utils/validators.dart';

/// Outcome of a sign-in or sign-up attempt.
class AuthResult {
  const AuthResult.ok([this.message]) : success = true;
  const AuthResult.failed(this.message) : success = false;

  final bool success;
  final String? message;
}

/// Account state for the app.
///
/// Security model:
///  * Passwords are sent straight to Supabase Auth over TLS and never stored,
///    logged, or cached by the app.
///  * The session token is owned by the Supabase SDK, which refreshes it and
///    persists it; the app only reads the resulting user id.
///  * Authorization is enforced by Postgres row-level security, not by this
///    class — see `supabase_setup.sql`.
///
/// When the build has no Supabase keys there is no password system at all:
/// the profile is a local demo identity, clearly labelled as such. Inventing
/// an offline "login" would mean inventing password storage on the device,
/// which is exactly the vulnerability this is meant to avoid.
class AuthState extends ChangeNotifier {
  AuthState();

  static const displayNameKey = 'profile_display_name';
  static const bioKey = 'profile_bio';
  static const cityKey = 'profile_city';
  static const avatarBase64Key = 'profile_avatar_b64';

  /// True when this build can create real accounts.
  static bool get supportsAccounts => AppInfo.backendConfigured;

  sb.User? _user;
  StreamSubscription<sb.AuthState>? _subscription;
  String _displayName = '';
  String _bio = '';
  String _city = '';
  String? _avatarUrl;
  Uint8List? _localAvatarBytes;
  bool _loading = true;
  bool _busy = false;
  bool _disposed = false;

  sb.User? get user => _user;
  sb.Session? get session => _user == null ? null : _client?.auth.currentSession;
  bool get loading => _loading;
  bool get busy => _busy;

  /// Signed in with a real email + password account.
  bool get isSignedIn => _user != null && !_user!.isAnonymous;

  /// Using the app without an account (anonymous session or demo mode).
  bool get isGuest => !isSignedIn;

  /// A build without Supabase keys: the profile lives only on this device.
  bool get isLocalOnlyMode => !supportsAccounts;

  /// True when the user can publish spots, post comments, and sync profile
  /// edits (either signed in with a real account, or running in local demo mode).
  bool get canContribute => isSignedIn || isLocalOnlyMode;

  /// Identifier matching `Spot.submittedById` for spots created by this user.
  String? get activeUserId =>
      isSignedIn ? _user?.id : (isLocalOnlyMode ? 'you' : null);

  String get email => _user?.email ?? '';
  String? get avatarUrl => _avatarUrl;
  Uint8List? get localAvatarBytes => _localAvatarBytes;

  String get displayName {
    final name = _displayName.trim();
    if (name.isNotEmpty) return name;
    final emailName = email.split('@').first;
    if (emailName.isNotEmpty) return emailName;
    return 'Explorer';
  }

  String get bio => _bio;

  String get city => _city;

  String get initials {
    final parts = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  /// A short, honest description of the current account state.
  String get statusLabel {
    if (isSignedIn) return 'Signed in';
    if (isLocalOnlyMode) return 'Local profile';
    return 'Guest';
  }

  sb.SupabaseClient? get _client {
    if (!supportsAccounts) return null;
    try {
      return sb.Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  Future<void> load() async {
    await _readPrefs();
    final client = _client;
    if (client != null) {
      _user = client.auth.currentUser;
      _adoptMetadata();
      if (isSignedIn) {
        await _fetchRemoteProfile();
      }
      _subscription = client.auth.onAuthStateChange.listen((event) {
        _user = event.session?.user ?? client.auth.currentUser;
        _adoptMetadata();
        if (isSignedIn) {
          _fetchRemoteProfile();
        }
        _loading = false;
        _notify();
      });
    }
    _loading = false;
    _notify();
  }

  Future<void> _readPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _displayName = prefs.getString(displayNameKey) ?? '';
      _bio = prefs.getString(bioKey) ?? '';
      _city = prefs.getString(cityKey) ?? '';
      final b64 = prefs.getString(avatarBase64Key);
      if (b64 != null && b64.isNotEmpty) {
        _localAvatarBytes = base64Decode(b64);
      }
    } catch (_) {
      // Defaults are fine; the profile is cosmetic without storage.
    }
  }

  Future<void> _fetchRemoteProfile() async {
    final client = _client;
    final userId = _user?.id;
    if (client == null || userId == null || !isSignedIn) return;
    try {
      final row = await client
          .from('profiles')
          .select('display_name, bio, city, avatar_url')
          .eq('id', userId)
          .maybeSingle();
      if (row == null) return;
      final remoteName = (row['display_name'] as String?)?.trim() ?? '';
      final remoteBio = (row['bio'] as String?)?.trim() ?? '';
      final remoteCity = (row['city'] as String?)?.trim() ?? '';
      final remoteAvatar = (row['avatar_url'] as String?)?.trim();
      if (remoteName.isNotEmpty) _displayName = remoteName;
      if (remoteBio.isNotEmpty) _bio = remoteBio;
      if (remoteCity.isNotEmpty) _city = remoteCity;
      if (remoteAvatar != null && remoteAvatar.isNotEmpty) {
        _avatarUrl = remoteAvatar;
      }
      await _writePrefs();
      _notify();
    } catch (_) {
      // Offline or unmigrated schema; keep local state.
    }
  }

  /// Prefers the name saved on this device, then the auth metadata.
  void _adoptMetadata() {
    final metadataName = _user?.userMetadata?['display_name'];
    if (_displayName.trim().isEmpty &&
        metadataName is String &&
        metadataName.trim().isNotEmpty) {
      _displayName = metadataName.trim();
    }
  }

  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    final emailError = Validators.email(email);
    if (emailError != null) return AuthResult.failed(emailError);
    if (password.isEmpty) return const AuthResult.failed('Enter your password.');

    final client = _client;
    if (client == null) {
      return const AuthResult.failed(
        'Accounts need the hosted backend. Use the demo profile for now.',
      );
    }

    _setBusy(true);
    try {
      final response = await client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      _user = response.user;
      _adoptMetadata();
      await _fetchRemoteProfile();
      _setBusy(false);
      return const AuthResult.ok('Welcome back.');
    } on sb.AuthException catch (error) {
      _setBusy(false);
      return AuthResult.failed(_messageFor(error));
    } catch (_) {
      _setBusy(false);
      return const AuthResult.failed(
        'Could not reach the server. Check your connection and try again.',
      );
    }
  }

  Future<AuthResult> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final nameError = Validators.displayName(name);
    if (nameError != null) return AuthResult.failed(nameError);
    final emailError = Validators.email(email);
    if (emailError != null) return AuthResult.failed(emailError);
    final passwordError = Validators.password(password);
    if (passwordError != null) return AuthResult.failed(passwordError);

    final client = _client;
    if (client == null) {
      return const AuthResult.failed(
        'Accounts need the hosted backend. Use the demo profile for now.',
      );
    }

    _setBusy(true);
    try {
      final response = await client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'display_name': name.trim()},
      );
      _user = response.user;
      _displayName = name.trim();
      await _writePrefs();

      if (response.session == null) {
        // Email confirmation is enabled on the project.
        _setBusy(false);
        return const AuthResult.ok(
          'Check your inbox to confirm your email, then sign in.',
        );
      }

      // The profile row is created by a database trigger; keep the name for
      // any surface that reads local state first.
      try {
        await client.from('profiles').upsert({
          'id': response.user!.id,
          'display_name': name.trim(),
        }, onConflict: 'id');
      } catch (_) {
        // The trigger remains the source of truth; this is a best-effort sync.
      }

      _setBusy(false);
      return const AuthResult.ok('Account created.');
    } on sb.AuthException catch (error) {
      _setBusy(false);
      return AuthResult.failed(_messageFor(error, signingUp: true));
    } catch (_) {
      _setBusy(false);
      return const AuthResult.failed(
        'Could not reach the server. Check your connection and try again.',
      );
    }
  }

  Future<void> signOut() async {
    final client = _client;
    if (client != null) {
      try {
        await client.auth.signOut();
      } catch (_) {
        // Even if the network call fails, drop local identity below.
      }
    }
    _user = null;
    _notify();
  }

  /// Saves the profile locally and, when signed in, mirrors it to the row this
  /// user owns. RLS rejects writing anyone else's row.
  Future<AuthResult> updateProfile({
    required String name,
    String? bio,
    String? city,
    Uint8List? avatarBytes,
    bool removeAvatar = false,
  }) async {
    final nameError = Validators.displayName(name);
    if (nameError != null) return AuthResult.failed(nameError);

    final trimmedBio = (bio ?? _bio).trim();
    if (trimmedBio.length > 140) {
      return const AuthResult.failed('Keep your bio under 140 characters.');
    }
    final trimmedCity = (city ?? _city).trim();
    if (trimmedCity.length > 80) {
      return const AuthResult.failed('Keep your home city under 80 characters.');
    }

    _displayName = name.trim();
    _bio = trimmedBio;
    _city = trimmedCity;
    if (removeAvatar) {
      _localAvatarBytes = null;
      _avatarUrl = null;
    } else if (avatarBytes != null && avatarBytes.isNotEmpty) {
      _localAvatarBytes = await compressForUpload(avatarBytes);
    }
    await _writePrefs();
    _notify();

    final client = _client;
    if (client != null && isSignedIn) {
      try {
        if (avatarBytes != null && avatarBytes.isNotEmpty) {
          final uploadBytes = _localAvatarBytes ?? avatarBytes;
          final path =
              'avatars/${_user!.id}/${DateTime.now().millisecondsSinceEpoch}.jpg';
          await client.storage.from('photos').uploadBinary(
                path,
                uploadBytes,
                fileOptions: const sb.FileOptions(contentType: 'image/jpeg'),
              );
          _avatarUrl = client.storage.from('photos').getPublicUrl(path);
        }
        await client.from('profiles').upsert({
          'id': _user!.id,
          'display_name': _displayName,
          'bio': _bio,
          'city': _city,
          'avatar_url': _avatarUrl,
        }, onConflict: 'id');
        try {
          await client.auth.updateUser(
            sb.UserAttributes(data: {'display_name': _displayName}),
          );
        } catch (_) {
          // Best-effort metadata mirror; profiles row is authoritative.
        }
      } catch (_) {
        return const AuthResult.failed(
          'Saved on this device. Syncing your profile failed.',
        );
      }
    }
    return const AuthResult.ok('Profile updated.');
  }

  /// Sends a password reset email when accounts are enabled.
  Future<AuthResult> sendPasswordReset(String email) async {
    final emailError = Validators.email(email);
    if (emailError != null) return AuthResult.failed(emailError);
    final client = _client;
    if (client == null) {
      return const AuthResult.failed(
        'Password reset needs the hosted backend.',
      );
    }
    _setBusy(true);
    try {
      await client.auth.resetPasswordForEmail(email.trim());
      _setBusy(false);
      return const AuthResult.ok(
        'If an account exists for that email, a reset link is on its way.',
      );
    } catch (_) {
      _setBusy(false);
      return const AuthResult.failed(
        'Could not send reset link right now. Please try again.',
      );
    }
  }

  /// Updates the signed-in user's password.
  Future<AuthResult> updatePassword(String newPassword) async {
    final err = Validators.password(newPassword);
    if (err != null) return AuthResult.failed(err);
    final client = _client;
    if (client == null || !isSignedIn) {
      return const AuthResult.failed('Sign in first to change your password.');
    }
    _setBusy(true);
    try {
      await client.auth.updateUser(sb.UserAttributes(password: newPassword));
      _setBusy(false);
      return const AuthResult.ok('Password updated.');
    } catch (_) {
      _setBusy(false);
      return const AuthResult.failed(
        'Could not update your password. You may need to sign in again first.',
      );
    }
  }

  /// Permanently deletes the signed-in account and local profile data
  /// (required for Google Play Data Safety compliance).
  Future<AuthResult> deleteAccount() async {
    final client = _client;
    if (client != null && isSignedIn) {
      _setBusy(true);
      try {
        await client.rpc('delete_own_account');
      } catch (_) {
        _setBusy(false);
        return const AuthResult.failed(
          'Could not delete your account right now. Please try again or contact support.',
        );
      }
      try {
        await client.auth.signOut();
      } catch (_) {}
      _setBusy(false);
    }

    _user = null;
    _displayName = '';
    _bio = '';
    _city = '';
    _avatarUrl = null;
    _localAvatarBytes = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(displayNameKey);
      await prefs.remove(bioKey);
      await prefs.remove(cityKey);
      await prefs.remove(avatarBase64Key);
    } catch (_) {}
    _notify();
    return const AuthResult.ok('Account deleted.');
  }

  Future<void> _writePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(displayNameKey, _displayName);
      await prefs.setString(bioKey, _bio);
      await prefs.setString(cityKey, _city);
      if (_localAvatarBytes != null && _localAvatarBytes!.length <= 250 * 1024) {
        await prefs.setString(
          avatarBase64Key,
          base64Encode(_localAvatarBytes!),
        );
      } else if (_localAvatarBytes == null) {
        await prefs.remove(avatarBase64Key);
      }
    } catch (_) {
      // Local persistence is best effort.
    }
  }

  void _setBusy(bool value) {
    _busy = value;
    _notify();
  }

  /// Deliberately vague: the UI must not reveal whether an email is registered.
  String _messageFor(sb.AuthException error, {bool signingUp = false}) {
    final code = error.code ?? '';
    if (signingUp) {
      return 'We could not create an account with those details. '
          'If you already have one, sign in instead.';
    }
    if (code == 'invalid_credentials' ||
        code == 'invalid_grant' ||
        error.message.toLowerCase().contains('invalid login')) {
      return 'Email or password is incorrect.';
    }
    if (code == 'email_not_confirmed') {
      return 'Confirm your email first — check your inbox.';
    }
    if (code == 'over_request_rate_limit' ||
        code == 'too_many_requests') {
      return 'Too many attempts. Wait a minute and try again.';
    }
    if (code == 'weak_password') {
      return 'Choose a stronger password.';
    }
    return 'Sign-in failed. Please try again.';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}

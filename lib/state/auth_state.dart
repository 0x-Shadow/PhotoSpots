import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../app_info.dart';
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
///    class — see `supabase_engagement.sql`.
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

  /// True when this build can create real accounts.
  static bool get supportsAccounts => AppInfo.backendConfigured;

  sb.User? _user;
  StreamSubscription<sb.AuthState>? _subscription;
  String _displayName = '';
  String _bio = '';
  String _city = '';
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

  String get email => _user?.email ?? '';

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
      _subscription = client.auth.onAuthStateChange.listen((event) {
        _user = event.session?.user ?? client.auth.currentUser;
        _adoptMetadata();
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
    } catch (_) {
      // Defaults are fine; the profile is cosmetic without storage.
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
  }) async {
    final nameError = Validators.displayName(name);
    if (nameError != null) return AuthResult.failed(nameError);

    _displayName = name.trim();
    if (bio != null) _bio = bio.trim();
    if (city != null) _city = city.trim();
    await _writePrefs();
    _notify();

    final client = _client;
    if (client != null && isSignedIn) {
      try {
        await client.from('profiles').update({
          'display_name': _displayName,
          'bio': _bio,
          'city': _city,
        }).eq('id', _user!.id);
      } catch (_) {
        return const AuthResult.failed(
          'Saved on this device. Syncing your profile failed.',
        );
      }
    }
    return const AuthResult.ok('Profile updated.');
  }

  Future<void> _writePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(displayNameKey, _displayName);
      await prefs.setString(bioKey, _bio);
      await prefs.setString(cityKey, _city);
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

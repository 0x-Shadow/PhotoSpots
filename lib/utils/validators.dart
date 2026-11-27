/// Small, testable validators. Keeping them out of widgets means the same
/// rules apply to the auth form and to any future entry point.
class Validators {
  Validators._();

  static final _email = RegExp(
    r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$',
  );

  /// Returns an error message, or null when the value is acceptable.
  static String? email(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return 'Enter your email.';
    if (email.length > 254) return 'That email is too long.';
    if (!_email.hasMatch(email)) return 'Enter a valid email address.';
    return null;
  }

  /// Minimum 8 characters with at least one letter and one number.
  static String? password(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Enter a password.';
    if (password.length < 8) return 'Use at least 8 characters.';
    if (password.length > 128) return 'Use 128 characters or fewer.';
    if (!RegExp(r'[A-Za-z]').hasMatch(password) ||
        !RegExp(r'[0-9]').hasMatch(password)) {
      return 'Include at least one letter and one number.';
    }
    return null;
  }

  static String? displayName(String? value) {
    final name = (value ?? '').trim();
    if (name.isEmpty) return 'Enter a display name.';
    if (name.length < 2) return 'Use at least 2 characters.';
    if (name.length > 32) return 'Use 32 characters or fewer.';
    return null;
  }

  static String? comment(String? value) {
    final body = (value ?? '').trim();
    if (body.isEmpty) return 'Write something first.';
    if (body.length > 500) return 'Keep comments under 500 characters.';
    return null;
  }
}

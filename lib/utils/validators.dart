import 'dart:typed_data';

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

  /// Ensures external URLs only use HTTPS so untrusted database values or
  /// overrides cannot trigger cleartext HTTP or non-HTTP schemes.
  static bool isSafeHttpsUrl(String? raw) {
    if (raw == null || raw.trim().isEmpty) return false;
    final uri = Uri.tryParse(raw.trim());
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        !uri.host.contains(' ');
  }

  /// Checks magic header bytes for JPEG, PNG, WebP, or ISO-BMFF (HEIC/HEIF)
  /// before uploading user bytes to public storage.
  static bool hasAllowedImageMagicBytes(Uint8List bytes) {
    if (bytes.length < 12) return false;
    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return true;
    // PNG: 89 50 4E 47 0D 0A 1A 0A
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return true;
    }
    // WebP: "RIFF"...."WEBP"
    if (bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }
    // HEIC/HEIF: ...."ftyp"
    if (bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      return true;
    }
    return false;
  }
}

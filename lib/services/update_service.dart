import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_info.dart';

/// A published release on the GitHub release channel.
class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.version,
    required this.notes,
    required this.pageUrl,
  });

  /// Raw release tag, e.g. `v1.1.0`.
  final String tag;

  /// Cleaned version, e.g. `1.1.0`.
  final String version;

  final String notes;
  final Uri pageUrl;
}

/// Checks the public GitHub releases endpoint for a version newer than the
/// running app.
///
/// The endpoint must be publicly readable: browser and device clients cannot
/// carry a secret API token. If the repository or its releases are private the
/// lookup fails silently and no prompt is shown.
class UpdateService {
  UpdateService._();

  static const _timeout = Duration(seconds: 6);

  /// Returns the newest release when it is newer than [AppInfo.version],
  /// otherwise `null`. Never throws.
  static Future<ReleaseInfo?> check() async {
    try {
      final response = await http
          .get(
            AppInfo.releasesApi,
            headers: const {'Accept': 'application/vnd.github+json'},
          )
          .timeout(_timeout);

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return null;

      final tag = (data['tag_name'] as String? ?? '').trim();
      if (tag.isEmpty) return null;

      final version = cleanVersion(tag);
      if (!isNewer(version, AppInfo.version)) return null;

      return ReleaseInfo(
        tag: tag,
        version: version,
        notes: (data['body'] as String? ?? '').trim(),
        pageUrl: AppInfo.releasesPage,
      );
    } catch (_) {
      // Update checks are best effort and must never block startup.
      return null;
    }
  }

  /// Strips a leading `v` and any pre-release/build suffix.
  static String cleanVersion(String tag) {
    var value = tag.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }
    final cut = value.indexOf(RegExp(r'[+\-]'));
    if (cut > 0) value = value.substring(0, cut);
    return value;
  }

  /// Semantic-ish comparison of dotted numeric versions.
  ///
  /// Returns true when [candidate] is greater than [current]. Missing parts are
  /// treated as zero, so `1.2` equals `1.2.0`.
  static bool isNewer(String candidate, String current) {
    final a = _parts(candidate);
    final b = _parts(current);
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av > bv) return true;
      if (av < bv) return false;
    }
    return false;
  }

  static List<int> _parts(String version) {
    return cleanVersion(version)
        .split('.')
        .map((part) => int.tryParse(part.replaceAll(RegExp(r'\D'), '')) ?? 0)
        .toList();
  }
}

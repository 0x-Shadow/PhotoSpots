import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../app_info.dart';

/// A published release on the GitHub release channel.
class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.version,
    required this.notes,
    required this.pageUrl,
    this.apkUrl,
    this.apkSize,
  });

  /// Raw release tag, e.g. `v1.1.0`.
  final String tag;

  /// Cleaned version, e.g. `1.1.0`.
  final String version;

  final String notes;
  final Uri pageUrl;

  /// Direct download link for the Android package attached to the release, when
  /// the release ships one. Lets the app install the update itself instead of
  /// sending the user to a browser.
  final Uri? apkUrl;

  /// Declared size of [apkUrl] in bytes, used for the download progress bar.
  final int? apkSize;

  bool get canSelfUpdate => apkUrl != null;
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

      final apk = _apkAsset(data['assets']);

      return ReleaseInfo(
        tag: tag,
        version: version,
        notes: (data['body'] as String? ?? '').trim(),
        pageUrl: AppInfo.releasesPage,
        apkUrl: apk?.url,
        apkSize: apk?.size,
      );
    } catch (_) {
      // Update checks are best effort and must never block startup.
      return null;
    }
  }

  static _ApkAsset? _apkAsset(Object? assets) {
    if (assets is! List) return null;
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = (asset['name'] as String? ?? '').toLowerCase();
      if (!name.endsWith('.apk')) continue;
      final url = asset['browser_download_url'] as String? ?? '';
      if (url.isEmpty) continue;
      return _ApkAsset(
        url: Uri.parse(url),
        size: asset['size'] as int?,
      );
    }
    return null;
  }

  /// Downloads the release APK to [target], reporting progress as it goes.
  ///
  /// Throws [UpdateDownloadException] with a user-safe message on failure. A
  /// partially written file is removed so a retry never installs a truncated
  /// package.
  static Future<File> downloadApk(
    ReleaseInfo release, {
    required File target,
    void Function(int received, int? total)? onProgress,
    FutureOr<bool> Function()? isCancelled,
  }) async {
    final url = release.apkUrl;
    if (url == null) throw const UpdateDownloadException('no-binary');

    final client = http.Client();
    IOSink? sink;
    var success = false;
    try {
      final response = await client
          .send(http.Request('GET', url))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw UpdateDownloadException('status-${response.statusCode}');
      }

      final total = response.contentLength ?? release.apkSize;
      if (target.existsSync()) target.deleteSync();
      target.parent.createSync(recursive: true);
      sink = target.openWrite();

      var received = 0;
      var lastReport = 0;
      await for (final chunk in response.stream) {
        if (isCancelled != null && await isCancelled()) {
          throw const UpdateDownloadException('cancelled');
        }
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null &&
            (received - lastReport > 256 * 1024 ||
                (total != null && received >= total))) {
          lastReport = received;
          onProgress(received, total);
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;

      if (total != null && received != total) {
        throw const UpdateDownloadException('incomplete');
      }

      success = true;
      return target;
    } on UpdateDownloadException {
      rethrow;
    } catch (_) {
      throw const UpdateDownloadException('network');
    } finally {
      client.close();
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      if (!success && target.existsSync()) {
        try {
          target.deleteSync();
        } catch (_) {}
      }
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

class _ApkAsset {
  const _ApkAsset({required this.url, required this.size});

  final Uri url;
  final int? size;
}

/// Failure of an in-app update download, carrying a stable [reason] code.
class UpdateDownloadException implements Exception {
  const UpdateDownloadException(this.reason);

  final String reason;

  bool get isCancelled => reason == 'cancelled';

  @override
  String toString() => 'UpdateDownloadException($reason)';
}

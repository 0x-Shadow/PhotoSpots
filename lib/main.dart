import 'dart:async';
import 'dart:convert' as convert;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/supabase_repository.dart';
import 'data/spot_repository.dart';
import 'screens/root_shell.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

// ---- Supabase configuration ----
// Create a free project at https://supabase.com, then paste your keys here.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

// Current app version — bump this on every release.
const _currentVersion = '1.0.1';

final _githubRepo = '0x-Shadow/PhotoSpots';
final _releasesApiUrl = 'https://api.github.com/repos/$_githubRepo/releases/latest';
final _releasesPageUrl = 'https://github.com/$_githubRepo/releases/latest';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase if keys are present.
  if (_supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
      url: _supabaseUrl,
      anonKey: _supabaseAnonKey,
    );
  }

  runApp(const PhotoSpotApp());
}

class PhotoSpotApp extends StatelessWidget {
  const PhotoSpotApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Choose repository: Supabase when configured, mock otherwise.
    final useSupabase = _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;

    return ChangeNotifierProvider(
      create: (_) {
        final state = AppState(
          useSupabase ? SupabaseSpotRepository() : MockSpotRepository(),
        );
        state.load();
        return state;
      },
      child: MaterialApp(
        title: 'PhotoSpot',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: UpdateChecker(child: RootShell()),
      ),
    );
  }
}

/// Checks for updates on every app open (lightweight, ~5 second timeout).
/// Shows a popup dialog with Update / Later options when a new release exists.
/// Stores the last checked version in local preferences so it doesn't nag
/// every single open — only when a newer release is published.
class UpdateChecker extends StatefulWidget {
  final Widget child;

  const UpdateChecker({super.key, required this.child});

  @override
  State<UpdateChecker> createState() => _UpdateCheckerState();
}

class _UpdateCheckerState extends State<UpdateChecker> {
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    // Check after the first frame so the app opens instantly.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates());
  }

  Future<void> _checkForUpdates() async {
    if (_dialogShown) return;

    final prefs = await SharedPreferences.getInstance();
    final lastNotifiedVersion = prefs.getString('last_notified_version');

    // Lightweight check — GitHub releases API, 5 second timeout.
    String? latestTag;
    String? releaseNotes;
    try {
      final response = await http.get(
        Uri.parse(_releasesApiUrl),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = convert.jsonDecode(response.body) as Map<String, dynamic>;
        latestTag = data['tag_name'] as String?;
        releaseNotes = data['body'] as String?;
      }
    } catch (_) {
      // Silent fail — update check is non-critical.
    }

    if (latestTag == null || latestTag.isEmpty) return;

    // Clean tag (strip leading 'v').
    final cleanTag = latestTag.startsWith('v')
        ? latestTag.substring(1)
        : latestTag;

    // Only notify if this version is newer than current AND we haven't already
    // notified about this specific version.
    final isNewer = _isVersionNewer(cleanTag, _currentVersion);
    final alreadyNotified = lastNotifiedVersion == latestTag;

    if (isNewer && !alreadyNotified && mounted && !_dialogShown) {
      _dialogShown = true;
      await _showUpdateDialog(
        latestTag: latestTag,
        cleanTag: cleanTag,
        releaseNotes: releaseNotes ?? 'New version available',
        prefs: prefs,
      );
    }
  }

  Future<void> _showUpdateDialog({
    required String latestTag,
    required String cleanTag,
    required String releaseNotes,
    required SharedPreferences prefs,
  }) async {
    final shouldUpdate = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              const Icon(Icons.update_rounded, color: AppColors.star, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Update Available',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Inter',
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Version $cleanTag is ready',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Inter',
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                releaseNotes,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontFamily: 'Inter',
                  fontSize: 13,
                  height: 1.4,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text(
                'Later',
                style: TextStyle(
                  color: AppColors.textFaint,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () async {
                // Mark this version as notified so we don't nag again.
                await prefs.setString('last_notified_version', latestTag);
                if (mounted) Navigator.of(dialogContext).pop(true);
                final url = Uri.parse(_releasesPageUrl);
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.action,
                foregroundColor: AppColors.onAction,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Update',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );

    // If user dismissed without choosing, still mark as notified to avoid spam.
    if (shouldUpdate != true && mounted) {
      await prefs.setString('last_notified_version', latestTag);
    }
  }

  /// Semantic version comparison: returns true if [candidate] is newer than [current].
  bool _isVersionNewer(String candidate, String current) {
    final cParts = candidate.split('.');
    final curParts = current.split('.');

    for (int i = 0; i < 3; i++) {
      final cVal = i < cParts.length ? int.tryParse(cParts[i]) ?? 0 : 0;
      final curVal = i < curParts.length ? int.tryParse(curParts[i]) ?? 0 : 0;
      if (cVal > curVal) return true;
      if (cVal < curVal) return false;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

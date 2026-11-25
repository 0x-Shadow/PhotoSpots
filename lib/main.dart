import 'dart:io';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
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
      child: Consumer<AppState>(
        builder: (context, appState, child) {
          return MaterialApp(
            title: 'PhotoSpot',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark,
            home: UpdateCheckGate(
              child: const RootShell(),
              updateMessage: appState.updateMessage,
              latestVersion: appState.latestVersion,
            ),
          );
        },
      ),
    );
  }
}

/// Shows an update message on first launch when a new version is available.
/// Light and fast — only checks GitHub releases API once per app start.
class UpdateCheckGate extends StatefulWidget {
  final Widget child;
  final String? updateMessage;
  final VersionInfo? latestVersion;

  const UpdateCheckGate({
    super.key,
    required this.child,
    this.updateMessage,
    this.latestVersion,
  });

  @override
  State<UpdateCheckGate> createState() => _UpdateCheckGateState();
}

class _UpdateCheckGateState extends State<UpdateCheckGate> {
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    // Show update message after first frame so the app loads instantly
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted && widget.updateMessage != null && widget.latestVersion != null) {
        setState(() => _showing = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_showing) return widget.child;

    return widget.child;
  }

  // We show the update as a SnackBar instead of blocking dialog — light & fast
  @override
  void didUpdateWidget(UpdateCheckGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_showing && widget.updateMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 6),
            backgroundColor: AppColors.surfaceElevated,
            content: Row(
              children: [
                const Icon(Icons.update_rounded,
                    color: AppColors.star, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'New version ${widget.latestVersion} available',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Inter',
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.updateMessage!,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontFamily: 'Inter',
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            action: SnackBarAction(
              label: 'Get it',
              textColor: AppColors.star,
              onPressed: () async {
                final url =
                    'https://github.com/0x-Shadow/PhotoSpots/releases/latest';
                if (await canLaunchUrl(Uri.parse(url))) {
                  await launchUrl(Uri.parse(url));
                }
              },
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );
      });
    }
  }
}

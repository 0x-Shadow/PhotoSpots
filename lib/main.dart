import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/spot_repository.dart';
import 'data/supabase_repository.dart';
import 'screens/root_shell.dart';
import 'screens/splash_screen.dart';
import 'state/app_state.dart';
import 'state/settings_state.dart';
import 'theme/app_theme.dart';
import 'widgets/update_gate.dart';

// ---- Supabase configuration ----
// Create a free project at https://supabase.com, then build with:
//   --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
const _supabaseAnonKey =
    String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

bool get _useSupabase =>
    _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_useSupabase) {
    await Supabase.initialize(
      url: _supabaseUrl,
      publishableKey: _supabaseAnonKey,
    );
  }

  runApp(const PhotoSpotApp());
}

class PhotoSpotApp extends StatefulWidget {
  const PhotoSpotApp({super.key});

  @override
  State<PhotoSpotApp> createState() => _PhotoSpotAppState();
}

class _PhotoSpotAppState extends State<PhotoSpotApp> {
  late final SpotRepository _repository;

  @override
  void initState() {
    super.initState();
    _repository =
        _useSupabase ? SupabaseSpotRepository() : MockSpotRepository();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AppState(_repository)..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => SettingsState()..load(),
        ),
      ],
      child: MaterialApp(
        title: 'PhotoSpot',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: const AppEntry(),
      ),
    );
  }
}

/// Shows the first-launch splash once, then the app guarded by the update
/// prompt.
class AppEntry extends StatefulWidget {
  const AppEntry({super.key});

  @override
  State<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<AppEntry> {
  static const _seenSplashKey = 'seen_splash';

  bool? _showSplash;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var seen = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      seen = prefs.getBool(_seenSplashKey) ?? false;
    } catch (_) {
      seen = false;
    }
    if (!mounted) return;
    setState(() => _showSplash = !seen);
  }

  Future<void> _finishSplash() async {
    setState(() => _showSplash = false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_seenSplashKey, true);
    } catch (_) {
      // The splash may show again if storage is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showSplash == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_showSplash == true) {
      return SplashScreen(onStart: _finishSplash);
    }

    return const UpdateGate(child: RootShell());
  }
}

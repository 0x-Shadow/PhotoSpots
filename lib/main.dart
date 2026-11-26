import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_info.dart';
import 'data/spot_repository.dart';
import 'data/supabase_repository.dart';
import 'screens/root_shell.dart';
import 'screens/splash_screen.dart';
import 'state/app_state.dart';
import 'state/settings_state.dart';
import 'theme/app_theme.dart';
import 'widgets/update_gate.dart';

// Backend configuration lives in AppInfo; both values are supplied at build
// time with --dart-define. Without them the app runs in demo mode.

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (AppInfo.backendConfigured) {
    await Supabase.initialize(
      url: AppInfo.supabaseUrl,
      publishableKey: AppInfo.supabaseAnonKey,
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
        AppInfo.backendConfigured ? SupabaseSpotRepository() : MockSpotRepository();
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
      child: _LocationResumeObserver(
        child: MaterialApp(
          title: 'PhotoSpot',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark,
          home: const AppEntry(),
        ),
      ),
    );
  }
}

/// A permission granted in system settings only takes effect after the app is
/// resumed. Rechecking here means the user never has to come back and tap the
/// location button again.
class _LocationResumeObserver extends StatefulWidget {
  const _LocationResumeObserver({required this.child});

  final Widget child;

  @override
  State<_LocationResumeObserver> createState() => _LocationResumeObserverState();
}

class _LocationResumeObserverState extends State<_LocationResumeObserver>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<AppState>().onAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
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

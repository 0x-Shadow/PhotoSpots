/// Single source of truth for app identity and the release channel.
///
/// Bump [version] together with `version:` in pubspec.yaml for every release.
/// The in-app update prompt compares this value with the latest GitHub release.
class AppInfo {
  AppInfo._();

  static const name = 'PhotoSpot';

  /// Current app version. Injected at build time when provided so CI can keep
  /// it in sync, otherwise the checked-in value is used.
  static const version = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.16',
  );

  /// Repository that owns the release channel. Forks must override it at build
  /// time (`--dart-define=GITHUB_REPO=your-name/your-repo`) so update prompts
  /// and release links never point at someone else's APKs.
  static const githubRepo = String.fromEnvironment(
    'GITHUB_REPO',
    defaultValue: '0x-Shadow/PhotoSpots',
  );

  // ---- Backend ----
  // Both are supplied at build time. Empty values put the app into demo mode,
  // where spots live in memory and nothing is shared with other devices.
  static const supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  /// Whether uploads can be stored and shared with other users.
  static bool get backendConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Shown on the profile until real accounts exist.
  static const handle = '0x-Shadow';

  /// Optional public mirror of the release metadata. Useful when the source
  /// repository is private, since unauthenticated clients cannot read it.
  static const releasesApiOverride =
      String.fromEnvironment('RELEASES_API_URL', defaultValue: '');

  static Uri get releasesApi => releasesApiOverride.isNotEmpty
      ? Uri.parse(releasesApiOverride)
      : Uri.parse('https://api.github.com/repos/$githubRepo/releases/latest');

  static const releasesPageOverride =
      String.fromEnvironment('RELEASES_PAGE_URL', defaultValue: '');

  static Uri get releasesPage => releasesPageOverride.isNotEmpty
      ? Uri.parse(releasesPageOverride)
      : Uri.parse('https://github.com/$githubRepo/releases/latest');

  static Uri get repoPage => Uri.parse('https://github.com/$githubRepo');

  /// Support contact shown in Legal & Support screens (Google Play policy).
  static const supportEmail = String.fromEnvironment(
    'SUPPORT_EMAIL',
    defaultValue: 'support@photospot.app',
  );

  /// Optional external legal URLs; in-app legal pages always work offline too.
  static const privacyPolicyUrl = String.fromEnvironment(
    'PRIVACY_POLICY_URL',
    defaultValue: '',
  );
  static const termsUrl = String.fromEnvironment(
    'TERMS_URL',
    defaultValue: '',
  );

  /// Sideload APK self-install is disabled by default for Google Play
  /// compliance (Play forbids `REQUEST_INSTALL_PACKAGES`). Set
  /// `--dart-define=ENABLE_SELF_UPDATE=true` only for direct GitHub APK builds.
  static const enableSelfUpdate = bool.fromEnvironment(
    'ENABLE_SELF_UPDATE',
    defaultValue: false,
  );
}

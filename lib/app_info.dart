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
    defaultValue: '1.0.4',
  );

  static const githubRepo = '0x-Shadow/PhotoSpots';

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
}

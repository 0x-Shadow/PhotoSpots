# PhotoSpot

A community map of the best photo spots. Browse the map, open a spot, save it,
and publish your own with a photo.

Flutter (iOS, Android, web) · `flutter_map` + CARTO dark tiles · provider ·
Supabase optional.

## Run

```bash
flutter pub get
flutter run                    # demo mode with Lisbon seed data
flutter run -d chrome          # web preview
```

Demo mode needs no keys and stores saved spots on the device. Publishing in demo
mode keeps the picked photo in memory for the session.

## Connect Supabase (real spots, saves, photo uploads, anonymous sessions)

1. Create a free project at <https://supabase.com>.
2. Run [`supabase_schema.sql`](supabase_schema.sql) in the SQL editor.
3. Authentication → Providers → enable **Anonymous sign-ins**.
4. Storage → create a public bucket named `photos`.
5. Build with:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR-ANON-KEY
```

Save and view counters are maintained by database triggers, so they cannot be
overwritten by concurrent clients.

## Releases and in-app updates

Publishing is one push. The `Publish release` workflow takes the base version
from `pubspec.yaml`, bumps the patch number until the tag is free, builds the
APK stamped with that version, and publishes the GitHub Release with
`photospot-<version>.apk` attached:

```bash
git commit -am "whatever changed"
git push origin main
```

So `version: 1.0.4+4` with `v1.0.4` already released produces `v1.0.5`, and the
next push produces `v1.0.6`. Pushing a `v*` tag still publishes that exact tag.

On launch the app asks the public GitHub Releases API for the latest release and
compares it with `AppInfo.version`. When it is newer the update dialog offers
**Update**, which downloads the release APK inside the app and hands it to the
Android package installer — no browser, no GitHub, no manual download:

- Progress is shown while downloading, and **Cancel** aborts cleanly.
- Android needs the user to allow installs for PhotoSpot once
  (`REQUEST_INSTALL_PACKAGES`); the dialog opens that setting and retries.
- iOS cannot install an app bundle from a download, so the dialog opens the
  release page there.
- "Later" snoozes that release for 24 hours. The whole check is controlled by
  **Profile → Preferences → Check for updates on launch**.

The releases endpoint must stay **publicly readable**: a private repository
returns 404 to unauthenticated clients, and the app cannot safely carry a
GitHub token. A different host works through overrides, as long as its JSON
keeps GitHub's shape (`tag_name`, `body`, `assets[].browser_download_url`):

```bash
flutter build apk --release \
  --dart-define=RELEASES_API_URL=https://your-host/releases/latest.json \
  --dart-define=RELEASES_PAGE_URL=https://your-host/downloads
```

## Structure

```
lib/
  app_info.dart              version + release channel
  services/update_service.dart  release lookup + APK download
  services/apk_installer.dart   Android package-installer bridge
  data/                      SpotRepository, mock seed, Supabase implementation
  models/spot.dart           spot, photo, ranking score
  state/                     AppState (spots/saves/location), SettingsState
  screens/                   splash, home, search, map, detail, saved,
                             categories, plan trip, profile, submit
  widgets/                   cards, rows, update gate, shared states
  theme/                     colors, type, motion
  utils/                     categories, formatting, actions, navigation
supabase_schema.sql          tables, RLS, triggers, storage policies, seed
.github/workflows/release.yml
```

## Checks

```bash
flutter analyze
flutter test
flutter build web --release
```

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

## Releases and in-app upgrade prompt

On launch the app asks the public GitHub Releases API for the latest release,
compares it with `AppInfo.version`, and offers an upgrade when it is newer.
"Later" snoozes that version for 24 hours. The check is controlled by
**Profile → Preferences → Check for updates on launch**.

To publish:

1. Bump `version:` in `pubspec.yaml` **and** `AppInfo.version`.
2. Commit, tag, and push (a tag push, not a plain branch push, is what creates
   a release):

```bash
git commit -am "Release v1.0.3"
git tag v1.0.3
git push origin main --tags
```

The `Publish release` workflow creates the GitHub Release from the tag. The app
does not need a signed build to *detect* the release; attach your built binaries
to the release separately.

> The releases endpoint must be **publicly readable**. A private repository
> returns 404 to unauthenticated clients, and an app cannot safely carry a
> GitHub token. Either keep the release channel public, or point the app at a
> public mirror of the release metadata:
>
> ```bash
> flutter build web --release \
>   --dart-define=RELEASES_API_URL=https://your-host/releases/latest.json \
>   --dart-define=RELEASES_PAGE_URL=https://your-host/downloads
> ```
>
> The JSON needs `tag_name` and `body`, matching GitHub's release shape.

## Structure

```
lib/
  app_info.dart              version + release channel
  services/update_service.dart
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

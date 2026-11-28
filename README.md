# PhotoSpot

**PhotoSpot is a community map for the places worth stepping out for.**

Find a golden-hour viewpoint, a great first-date walk, a quiet photo location,
or the kind of local corner that does not appear in a generic travel list.
People who discover a place can share it with a photo and a few useful details;
everyone else can save it, plan around it, and get directions.

> A map of real recommendations, not a feed of filler.

## What works today

- Browse an interactive, dark-mode map with searchable, filterable place pins.
- Discover community favourites, golden-hour spots, date ideas, photo walks,
  nature, nightlife, and more.
- Open a place for photos, route directions, distance, ratings, save actions,
  and shareable map links.
- Save places locally, build a short trip plan, and revisit your favourites.
- Publish a spot in three focused steps: photo, location, details. When the
  original file carries GPS data the pin, address, and city are filled in
  automatically; a visitor tip, time of day, and tags are optional.
- Respectful permissions: location is requested only when a person asks to use
  it or shares a place—not on app launch.
- Run fully in demo mode, or connect Supabase for real community data, saves,
  likes, and comments. Publishing a spot or photo requires a signed-in account;
  browsing never does.

## Product principles

PhotoSpot should be useful in the moment and responsible over time:

1. **Fast to share.** Contributing should take less effort than writing a post.
2. **Useful detail beats engagement bait.** The best time, exact angle, and a
   thoughtful note matter more than likes.
3. **Respect places.** Sensitive locations need clear privacy and precision
   controls before this is opened to a wider community.
4. **People first.** No AI-generated spot feed or fake recommendations.

## Screens

| Area | What it is for |
| --- | --- |
| Welcome | Explains the app through sunset views, date nights, and hidden corners. |
| Home | Community highlights, golden-hour discovery, categories, and nearby picks. |
| Map | Pins, photo pins, filters, search, sorting, current-location control, and a place preview. |
| Search | Search places, cities, descriptions, and tags. |
| Spot detail | Photos, useful facts, save/share/directions actions, and community context. |
| Saved | A personal shortlist, with swipe-to-remove and sorting. |
| Plan a trip | A lightweight collection for an upcoming outing. |
| Profile & settings | Preferences for updates, units, and photo map pins. |
| Publish | Camera/gallery upload, EXIF-placed pin, and a low-friction publishing flow. |

## Tech stack

- [Flutter](https://flutter.dev/) for Android, iOS, web, and desktop targets
- [flutter_map](https://pub.dev/packages/flutter_map) with Esri's dark basemap,
  a CARTO option, and an OpenStreetMap fallback
- `provider` for app state
- [Supabase](https://supabase.com/) for production spots, storage, email
  accounts, saves, comments, and server-owned counters
- `geolocator`, `image_picker`, and `url_launcher` for native capabilities

## Run locally

### Prerequisites

- Flutter SDK matching the version in CI (currently 3.47.7)
- Android Studio/Xcode only when running on their respective platforms

```bash
git clone https://github.com/0x-Shadow/PhotoSpots.git
cd PhotoSpots
flutter pub get
flutter run
```

Without backend values the app starts in **demo mode** with Lisbon seed data.
Saves remain on the device; a submitted photo exists only for that app session.

```bash
flutter test
flutter analyze
```

## Connect a real community backend

PhotoSpot uses Supabase only when both build-time values are present:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR-PUBLISHABLE-ANON-KEY
```

Set up the project before inviting real contributors:

1. Create a Supabase project.
2. Paste [`supabase_setup.sql`](supabase_setup.sql) into the SQL editor and run
   it. It is completely idempotent and can be re-run safely at any time.
3. No auth provider changes are needed: the app never signs in anonymously.
   Publishing, saving, and commenting require a normal email account, which
   keeps every write attributable.
4. The script creates the public `photos` storage bucket with an 8 MB per-file
   limit, an image-only MIME allowlist, and a daily upload rate limit. To seed
   the demo photos, set your project ref in the seed section of
   [`supabase_setup.sql`](supabase_setup.sql) and upload the images to
   `photos/seed/` first; leaving it null skips photo seeding.
5. Confirm your Row Level Security policies before production. The included
   schema is the starting point—not a substitute for moderation and abuse
   controls.

Counters, ratings, and review counts are server-owned: table-wide insert/update
is revoked and only the columns a person may set are granted back, views are one
row per viewer per spot, and photo rows are limited by size, MIME type, and
upload rate on both the client and the server. Other people can only see a
profile's display name, avatar, and the content it contributed—bio and home
city stay private to the owner. Report-based auto-hides need five distinct
reporters, ignore self-reports, and can be contested by the owner through the
`appeal_hidden_content` RPC, which logs an audit row in `moderation_appeals`.

## Permissions and privacy

| Permission | Why it is requested | When |
| --- | --- | --- |
| Location | Center the map, calculate nearby spots, and place a shared spot. | When the person uses location or starts sharing. |
| Camera | Capture a new spot photo. | After choosing **Camera**. |
| Photo library | Select a cover photo to share. | After choosing **Gallery**. |

No permission is required to browse the app. Before store submission, publish a
privacy policy explaining photo storage, device identifiers, approximate vs.
exact location, retention, reporting, and account deletion.

## Release APK

The repository has a GitHub Actions release workflow. A push to `main` resolves
the next free patch version, builds an APK, creates a GitHub Release, and
attaches `photospot-<version>.apk`.

For a local signed release, configure an ignored `android/key.properties` that
points at your long-lived Android signing key, then run:

```bash
flutter build apk --release \
  --dart-define=APP_VERSION=1.0.16 \
  --dart-define=ENABLE_SELF_UPDATE=true \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR-PUBLISHABLE-ANON-KEY
```

`ENABLE_SELF_UPDATE=true` also has to be visible to Gradle as an environment
variable (`ENABLE_SELF_UPDATE=true flutter build apk ...` on macOS/Linux,
`$env:ENABLE_SELF_UPDATE="true"` on PowerShell) so the Android manifest
declares `REQUEST_INSTALL_PACKAGES`. Without it the build stays Play-safe and
never asks to install packages. Forks should also pass
`--dart-define=GITHUB_REPO=your-name/your-repo` so update checks, release
links, and the repository page point at your own repository instead of the
upstream one.

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`.

For GitHub Actions, configure these repository secrets:

- `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
  `ANDROID_KEY_PASSWORD`
- `SUPABASE_URL`, `SUPABASE_ANON_KEY`

The release channel must stay publicly readable for in-app update checks.
Every push to `main` also runs [`.github/workflows/ci.yml`](.github/workflows/ci.yml)
(`flutter analyze`, `flutter test`, and a web build), and the release job refuses
to publish unless those checks pass.

## Before App Store and Play Store launch

The code can produce a release APK today, but a public community app needs a
few product and operational protections before submission:

- Add reporting, blocking, and moderator review. Accounts exist, and owners can
  already appeal an automatic report-based hide (`moderation_appeals`), but
  there is no moderator queue yet.
- Add duplicate/place-quality checks and a way to correct a spot (owners can
  already delete their own spots and photos).
- Add an option to blur or hide exact coordinates for sensitive locations.
- Publish Terms, Privacy Policy, Community Guidelines, and a support contact.
- Set up crash reporting, analytics with consent, store screenshots, and real
  device testing.
- Build an Android App Bundle (`flutter build appbundle`) for Google Play and
  archive/sign through Xcode for the App Store.

## Contributing

Issues and pull requests are welcome. For UI work, keep the dark “night atlas”
system: cinematic imagery, deliberate motion, strong contrast, 44px+ tap
targets, and no generic card clutter.

Before opening a PR:

```bash
flutter analyze
flutter test
```

For security concerns, please do not open a public issue containing exploit
details or credentials. Contact the maintainer privately first.

## Project structure

```text
lib/
  data/       repository implementations and Supabase integration
  map/        basemap registry, tile layers, and attribution
  models/     spot, photo, and comment domain models
  screens/    splash, shell, home, map, search, categories, detail, saved,
              profile, settings, auth, plan trip, publish
  services/   geocoding, EXIF GPS reading, photo compression, in-app updates
  state/      app, auth, settings, and location state
  theme/      visual tokens and motion
  widgets/    reusable cards, pins, forms, and state views
supabase_setup.sql        complete schema, RLS, storage, triggers, and seed data
.github/workflows/        CI gate and signed APK release automation
```

## License

Released under the [MIT License](LICENSE).

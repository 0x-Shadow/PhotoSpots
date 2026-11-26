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
- Publish a spot in two focused steps: pick a photo, add the name and city,
  then publish. A visitor tip, time of day, and tags are optional.
- Respectful permissions: location is requested only when a person asks to use
  it or shares a place—not on app launch.
- Run fully in demo mode, or connect Supabase for real community data, uploads,
  saves, and anonymous publishing.

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
| Share a spot | Camera/gallery upload and a low-friction publishing flow. |

## Tech stack

- [Flutter](https://flutter.dev/) for Android, iOS, web, and desktop targets
- [flutter_map](https://pub.dev/packages/flutter_map) with CARTO dark tiles and
  OpenStreetMap attribution
- `provider` for app state
- [Supabase](https://supabase.com/) for production spots, storage, anonymous
  sessions, saves, and counters
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
flutter run -d chrome
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
2. Run [`supabase_schema.sql`](supabase_schema.sql) in the SQL editor.
3. Enable **Anonymous sign-ins** under Authentication → Providers.
4. Create a public storage bucket named `photos`.
5. Confirm your Row Level Security policies before production. The included
   schema is the starting point—not a substitute for moderation and abuse
   controls.

The supplied schema keeps saves and view counters server-controlled. Publishing
uses an anonymous session so the app can attribute and secure each write without
putting a login wall in front of a contribution.

## Permissions and privacy

| Permission | Why it is requested | When |
| --- | --- | --- |
| Location | Center the map, calculate nearby spots, and place a shared spot. | When the person uses location or starts sharing. |
| Camera | Capture a new spot photo. | After choosing **Camera**. |
| Photo library | Select a cover photo to share. | After choosing **Gallery**. |

No permission is required to browse the app. Before store submission, publish a
privacy policy explaining photo storage, anonymous identifiers, approximate vs.
exact location, retention, reporting, and account deletion.

## Release APK

The repository has a GitHub Actions release workflow. A push to `main` resolves
the next free patch version, builds an APK, creates a GitHub Release, and
attaches `photospot-<version>.apk`.

For a local signed release, configure an ignored `android/key.properties` that
points at your long-lived Android signing key, then run:

```bash
flutter build apk --release \
  --dart-define=APP_VERSION=1.0.4 \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR-PUBLISHABLE-ANON-KEY
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`.

For GitHub Actions, configure these repository secrets:

- `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
  `ANDROID_KEY_PASSWORD`
- `SUPABASE_URL`, `SUPABASE_ANON_KEY`

The release channel must stay publicly readable for in-app update checks.

## Before App Store and Play Store launch

The code can produce a release APK today, but a public community app needs a
few product and operational protections before submission:

- Add sign-in/profile ownership, reporting, blocking, and moderator review.
- Add duplicate/place-quality checks and a way to correct or remove a spot.
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
  models/     spot and photo domain models
  screens/    welcome, discovery, map, search, saved, profile, share
  services/   in-app update support
  state/      application and preference state
  theme/      visual tokens and motion
  widgets/    reusable place cards, rows, and states
supabase_schema.sql   database, RLS, storage, counters, and seed data
.github/workflows/   signed APK release automation
```

## License

Choose and add an open-source license before accepting outside contributions.
MIT is a simple permissive default; Apache-2.0 is another strong option when
you want an explicit patent grant.

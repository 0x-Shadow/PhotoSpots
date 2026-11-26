# PhotoSpot — Map repair, permission fix, and UI redesign pass

Date: 2026-11-26
Status: approved for planning
Scope: fix the dead basemap, make location permissions work, and redesign the
navigation, motion, update prompt, settings, spot detail, and the add-a-place
flow.

## 1. Problem

1. **The map is unusable.** CARTO ended anonymous tile access. Every request to
   `basemaps.cartocdn.com` returns HTTP 200 with a 256×256 PNG watermark reading
   "API KEY REQUIRED — carto.com/basemaps/apikey" (verified: identical response
   for every zoom, x/y, subdomain, retina suffix and user-agent). The screen
   becomes a wall of that text; photo pins render correctly on top.
2. **Location never gets granted.** `AppState.requestLocation()` returns a bool
   and a string. When permission is `deniedForever` or location services are
   off it only shows a SnackBar — there is no action that opens system settings,
   no explanation before the system prompt, no re-check when the app resumes,
   and the last fix is never cached, so every launch re-asks.
3. **The UI reads as generic.** Tokens exist in `AppTheme`/`AppMotion` but
   screens hand-write ~50 inline `TextStyle(... fontFamily: 'Inter')` blocks;
   two route-transition systems compete (`FadeUpwardsPageTransitionsBuilder`
   theme default vs `AppMotion.slideUp`); the tab switch is a flat opacity blink;
   the bottom bar has no selected indicator and its floating Add button
   disappears on two tabs and overlaps map content.
4. **Settings are confusing and partly duplicated.** "Preferences" (bottom
   sheet) and "App Settings" (dialog) are separate surfaces with a gear that
   duplicates a row; the manual "Check for updates" reimplements the updater
   with plain `AlertDialog`s, bypassing snooze and the in-app installer;
   switches use a white thumb on a green track; "Collections" counts distinct
   tags across *all* spots, not the user's; "Visited" resets every launch.
5. **Add-a-place is tedious and wrong.** `_LocationStep` (full map with
   pin-drop, "use my location", lat/lng readout) and `_ReviewStep` exist but are
   never instantiated — dead code. City is a required field pre-filled with
   "Lisbon", so a spot published without GPS silently lands in Lisbon.
6. **Spot detail and the update prompt look unfinished.** Fact tiles show
   filler values, back/share float over the hero and scroll away, saves count is
   gated on an unrelated `city.isNotEmpty` condition, and the update dialog
   hand-writes every style inline.

## 2. Goals / non-goals

**Goals**

- A basemap that renders everywhere with no API key, no signup, and no paid
  service.
- Location permission that can actually be granted, explained, and repaired,
  with an instant fix on later launches.
- One design system actually used by every screen in this pass, with one motion
  language.
- A navigation bar with a real selected state and an always-available Add
  action.
- One Settings surface; one update-prompt implementation.
- A 3-step add-a-place flow where the location comes from the map (search or
  tap) and City is derived, never typed.
- A "share my exact location" action.

**Non-goals (explicitly out of scope)**

- No router rewrite (no `go_router`), no feature-folder restructuring, no
  accounts/auth, no clustering, no offline tiles, no reviews system.
- No paid service of any kind; every new dependency must be free and keyless.
- No rename of the product (the working name stays "PhotoSpot"; stray
  "findr."/"p." references are normalised to PhotoSpot, not rebranded).

## 3. Constraints

- Free stack only (binding, confirmed in PRODUCT.md).
- Aesthetic bar: Apple-level restraint; the near-black + amber-glow treatment
  must not survive.
- Text contrast and ≥44dp touch targets are standing requirements.
- Existing behaviour that works (saves, ranking, repository layer, update
  snooze, release flow) must not regress; `flutter analyze`, `flutter test`
  and `flutter build web --release` must pass.

## 4. Design

### 4.1 Basemap: styles, probe, fallback

New `lib/map/tile_sources.dart`:

```dart
class MapStyle {
  final String id;          // 'dark' | 'street' | 'carto'
  final String label;
  final String urlTemplate;
  final List<String> subdomains;
  final int maxZoom;
  final bool yBeforeX;      // Esri uses {z}/{y}/{x}
  final String attribution; // single-line, shown in the attribution widget
  final bool requiresKey;
}
```

Registry contents:

| id | Source | Key | Notes |
|---|---|---|---|
| `dark` (default) | Esri `Canvas/World_Dark_Gray_Base` + `Canvas/World_Dark_Gray_Reference` overlay | none | two stacked `TileLayer`s; verified dark with labels |
| `street` | `tile.openstreetmap.org` | none | fallback and light option |
| `carto` | current `dark_all` URL + `?api_key=<key>` | optional | selectable in Settings once a key is saved; never a default and never auto-probed |

Behaviour:

- New pref `map_style` (default `dark`), plus optional `carto_api_key` (empty by
  default; the CARTO row is hidden while empty).
- **Probe**: on first map build, `GET` one known tile of the active style with a
  5s timeout. Treat as unavailable when the status is not 200, the body is not
  an image, or — for CARTO — the body matches the known watermark digest
  (`df9307c738f2c6dbc0f8d31837019f98`, the md5 of the "API KEY REQUIRED"
  tile).
- On failure: switch to `street` for the session and show a dismissible inline
  chip: "Basemap unavailable — using OpenStreetMap."
- If the fallback also fails: render a **"Map tiles unavailable"** panel over
  the map background with the active style name and a Retry button. No silent
  black screen.
- One shared attribution widget renders the active style's attribution; both
  the map screen and the add-place map use it.
- Markers, user dot, selection card and filters are untouched by the probe.

### 4.2 Location permissions

`AppState.requestLocation()` returns a typed result:

```dart
enum LocationOutcome { granted, servicesOff, blocked, denied, failed }
```

- `servicesOff` → UI offers "Open location settings" →
  `Geolocator.openLocationSettings()`.
- `blocked` (`deniedForever`) → UI offers "Open settings" →
  `Geolocator.openAppSettings()`.
- `denied` → a pre-permission sheet (one-line rationale, *Allow* / *Not now*)
  is shown **before** `Geolocator.requestPermission()`. *Not now* resolves to
  `denied` without prompting the system.
- `granted` → position is written to prefs (`last_lat`, `last_lng`, `last_fix_at`)
  and loaded at startup, so `referenceLocation` is real on the next launch
  without any prompt. Lisbon remains only as a last-resort seed for demo data.
- An `AppLifecycleState.resumed` listener re-checks silently: if permission is
  now granted and no fix is cached, fetch one.
- All error strings move to the outcome enum; callers (map screen, add-place,
  settings) render the message **and** the matching action button.

### 4.3 Design system and motion

- **`AppTypography`**: `display / headline / title / body / label / caption`,
  each a `TextStyle` built from Inter with fixed sizes, weights and letter
  spacing, published through `ThemeData.textTheme`. Screens in this pass use
  `Theme.of(context).textTheme.*` or the `AppTypography` accessors — no inline
  `fontFamily: 'Inter'`.
- **Colour**: graphite scale retained (`background #0A0A0B`, `surface #161618`,
  `surfaceElevated #1D1D20`, hairline, textPrimary/Secondary/Faint). The amber
  accent (`#FFA94D`) is removed from interactive use and kept **only** for star
  ratings (`AppColors.star`). Selection/interactive accent becomes
  `AppColors.accent = #0A84FF`. White pill actions (`action`/`onAction`) stay.
- **Spacing/radius**: `space = 4/8/12/16/20/24`, `radius = 12/16/22`, already
  declared as `AppLayout` constants and used everywhere in this pass. Sections
  are separated by hairlines rather than nested cards.
- **Motion**: `AppMotion` is the single transition system.
  - `pageTransitionsTheme` no longer forces `FadeUpwardsPageTransitionsBuilder`;
    the default push is `AppMotion.slideUp` on every platform.
  - Tab switch: cross-fade **plus** a 0.98 → 1.0 scale on the incoming screen
    (220ms, `easeOutCubic`), replacing the opacity-only blink.
  - Existing capped stagger reveals and `PressButton` stay; `RevealItem`
    continues to honour `MediaQuery.disableAnimations`.
  - Dead API removed: `AppMotion.staggerDelay`'s unused parameter.

### 4.4 Navigation

- Bottom bar becomes **five slots: Home · Map · [Add] · Saved · Profile**.
  - The Add action is a raised circular button occupying the middle slot —
    always visible on every tab, opening `SubmitScreen` as today. The
    floating `FAB` is removed from both layouts, so nothing overlaps the map or
    list content.
  - Selected item: animated pill indicator (rounded rect, 120ms) behind the
    filled icon, label always visible, 48dp minimum target, hairline top
    border, translucent backdrop (`BackdropFilter` blur) so the bar reads over
    the map.
- Wide layout (`≥ kWideBreakpoint`): `NavigationRail` keeps its structure but
  gains the same indicator treatment; Add becomes the rail's leading action
  button.
- Accessibility: each item keeps `Semantics(button, selected, label)`; the Add
  button is labelled "Add a spot".

### 4.5 Update prompt and Settings

- **One implementation**: `lib/widgets/update_sheet.dart` renders the update
  prompt as a bottom sheet — release title, version you're on, release notes
  (or the honest fallback copy), progress with percentage while downloading,
  phases *downloading → installing → needs-permission → failed* with their
  existing recovery actions (*Update now*, *Later*, *Release page*, *Allow
  PhotoSpot to install updates*). Snooze keys, 24h window and APK install
  behaviour are unchanged. `UpdateGate` keeps orchestration and delegates
  presentation; the profile screen's hand-rolled dialogs are deleted.
- **One Settings surface**: `lib/screens/settings_screen.dart`, pushed from the
  profile gear **and** a single "Settings" row (the Preferences sheet and the
  App Settings dialog are removed). Sections:
  - **Map** — style picker listing Dark and Street always, plus a CARTO row with
    a paste-a-key field; choosing CARTO without a saved key is refused with an
    inline hint, and saving a key makes the style selectable. Photo-pin toggle.
  - **Distances** — metric / imperial.
  - **Updates** — check-on-launch toggle, *Check now* (reuses the shared update
    flow, including install), current version.
  - **Location** — permission status (Granted / Blocked / Services off) with the
    matching action button, or a link to grant it.
  - **About** — release channel, repository link, data source (demo vs
    Supabase).
- Switch styling: accent-coloured track, white thumb, on-brand in both states.
- Honest stats on the profile: "Collections" = number of saved spots; "Visited"
  is relabelled to reflect that it resets per session (or replaced by the
  saved-spot count) — no stat may claim data the app does not hold.

### 4.6 Spot detail

- Sticky top bar that fades in once the hero scrolls away: back, share,
  (spacer), so both actions are always reachable.
- Content order: hero gallery (unchanged behaviour, incl. counter pill) →
  title block → rating row with distance (measured from the reference location
  — the cached fix when present, otherwise the seeded demo city, which is
  labelled by name rather than implied to be the user) → **mini-map row**: a non-interactive 120pt `FlutterMap`
  showing the pin, tapping it opens the Map tab centred on the spot → facts
  (best time / category / saves — each label reflects what it actually shows)
  → description → tags → photo strip.
- Bottom action bar: Save (icon toggle) + **Share** (icon, native share sheet
  with the spot's maps link) + Directions (white pill). Share replaces the
  current clipboard-only behaviour.
- All type through `AppTypography`; sections divided by hairlines; the
  unrelated `city.isNotEmpty` condition gating the saves count is removed.

### 4.7 Add-a-place: three steps

`_stepTitles = ['Photo', 'Location', 'Details']`; the progress indicator shows
exactly three segments (today it implies a third step that does not exist).

1. **Photo** — gallery/camera as today; picking auto-advances. Gate: a photo is
   required.
2. **Location** — full-screen map (the currently dead `_LocationStep`, revived
   and rewritten):
   - Search field with debounced (500ms) queries against **Photon**
     (`https://photon.komoot.io/api/?q=…`) — free, keyless, returns name, city,
     country. Results render as a tappable list; selecting one flies the map
     there.
   - *Use my location* button (same permission flow as 4.2).
   - **Tap the map to place/move the pin**; dragging updates it. A draggable
     marker + readout show the current address.
   - Reverse geocode (`https://photon.komoot.io/reverse?lat=…&lon=…`) resolves
     the pin into an address chip and **auto-fills City**.
   - Initial pin: cached last fix → otherwise the visible map centre. Never the
     Lisbon fallback without saying so.
   - Geocoder failure is non-fatal: the pin stays draggable and City falls back
     to a manual field with an inline hint.
3. **Details** — Name (prefilled from search/reverse result, editable, required),
   *Tip* (optional), *Best time* (optional chips), *Tags* (optional chips).
   Publish is disabled until a name exists, with inline text explaining why —
   no silent grey button. Tapping Publish opens a compact confirmation sheet
   (photo, name, city, pin address) with *Publish* / *Keep editing*.

Data: `Spot` creation keeps its current signature; `city` comes from the
reverse-geocoded pin, `location` from the chosen pin.

### 4.8 Share my exact location

- New button on the map (below *Go to my location*, same 46dp treatment,
  semantic label "Share my location").
- Opens the native share sheet via **`share_plus`** (new dependency, free,
  official Flutter plugin) with text
  `My location: <lat>, <lon>` and link
  `https://www.google.com/maps/search/?api=1&query=<lat>,<lon>`.
- If sharing cannot start (e.g. web without a share target), copy the link to
  the clipboard and confirm with a SnackBar. Hidden until a fix exists.

## 5. Data and dependencies

- New prefs: `map_style`, `carto_api_key`, `last_lat`, `last_lng`,
  `last_fix_at` (all with safe defaults and try/catch writes, matching
  existing style).
- New dependency: `share_plus`. Geocoding uses the existing `http` package.
- No new services, accounts, or keys.

## 6. Error handling

| Failure | Behaviour |
|---|---|
| Tile probe fails | session fallback to OSM + dismissible chip |
| All tile styles fail | "Map tiles unavailable" panel + Retry |
| Geocoder down / offline | pin drag still works; City falls back to a manual field |
| Location services off / blocked | outcome enum + action button opening the right settings page |
| Update download/install fails | existing phase copy, now in the shared sheet |
| Share fails | clipboard fallback + confirmation |
| Publish fails | existing error SnackBar, unchanged |

## 7. Testing and verification

- `flutter analyze` — clean.
- `flutter test` — existing 19 tests green; tests asserting removed layouts
  (Preferences sheet, App Settings dialog, FAB placement) updated to the new
  surfaces.
- New tests:
  - tile-style registry: default selection, watermark digest detection,
    fallback ordering (unit);
  - `LocationOutcome` mapping and prefs caching (unit);
  - Photon response parsing from a fixture (unit);
  - add-place validation: photo gate, name gate, city auto-fill (widget);
  - settings round-trip for `map_style` (unit).
- `flutter build web --release` succeeds.
- Manual pass on a device: map renders, pins selectable, permission
  grant → deny → blocked → settings → grant loop works, add flow completes
  with a searched and a tapped location, share sheet opens.

## 8. Acceptance criteria

1. The map renders real geography with no API key and no signup, and shows a
   clear retryable state if it cannot.
2. A user can grant location from inside the app, repair a blocked permission
   from inside the app, and get an instant fix on the next launch.
3. Every screen in this pass uses `AppTypography`, the accent token, and
   `AppMotion` — no inline Inter styles, no second transition system.
4. The bottom bar shows a clear selected state and offers Add on every tab.
5. Settings exist on one screen; the update prompt exists once and is used by
   both entry points.
6. Publishing a place takes three steps, requires only a photo and a name, and
   never asks the user to type a city.
7. The user can share their exact location from the map in one tap.

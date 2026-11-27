# PhotoSpot — Build Plan

## Status: v1 complete, redesigned against the `findr.` reference

### Visual system
Near-black ground, raised dark cards, hairline borders, pure white display type,
white pill actions, amber ratings, dark CARTO map tiles. Reference-matched
layouts for splash, home, map, spot detail, categories, saved, profile, and
plan-your-trip. Motion is restrained: fade/slide routes and capped staggered
list reveals, with reduced-motion support.

### Functional surface
- Splash on first launch, then the tab shell (bottom tabs on phones, rail on
  wide screens).
- Home: trending spot, four category tiles, top picks nearby (real distance
  ordering), live search screen.
- Map: category icon pins culled to the viewport, filter chips, sorting
  (nearest/rated/saved), location button, floating spot card, save toggle.
- Spot detail: gallery, facts, description, photo strip, tags, share (clipboard
  link), directions (platform maps), save.
- Saved: sorting, swipe-to-remove, local persistence across restarts.
- Publish: three steps (photo → location → details), photo required, EXIF GPS
  places the pin when present, gallery picker plus a draggable map, review,
  downscaled upload to Supabase Storage when configured; bytes are kept locally
  in demo mode.
- Profile: real stats, preferences (updates/units/map pins), app settings and
  manual update check, plan-your-trip itinerary.
- Updates: public GitHub release check on launch with 24h snooze; tag-driven
  release workflow.

### Data
`SpotRepository` with `MockSpotRepository` (12 Lisbon seed spots) and
`SupabaseSpotRepository` (anonymous sessions, Postgres, Storage). Server-owned
save/view counters via triggers. Saved IDs persist locally and sync to Supabase
when a session exists.

### Verification
- `flutter analyze` — clean
- `flutter test` — 83 tests passing (ranking, persistence, submit bytes,
  EXIF GPS, version comparison, responsive flows)
- `flutter build web --release` — succeeds
- CI runs analyze, tests, and a web build on every PR and push to `main`; the
  release workflow runs the same checks before it will publish an APK.

### Known constraint
The in-app update check needs a public release channel. The GitHub repo must be
public, or `RELEASES_API_URL` / `RELEASES_PAGE_URL` must point at a public
mirror. See README.

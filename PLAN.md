# PhotoSpot — Build Plan

## Status: v1 BUILD COMPLETE — Professional Redesign Done

## What was rebuilt (findr. reference aesthetic)

**Visual world** — near-black ground (#0A0A0B), raised dark cards (#161618), 1px hairline borders, pure white display type (Inter), amber star ratings, white pill actions. Zero glow, zero glass, zero rounded floating cards — photos lead, chrome recedes.

**Animations** (per impeccable/animate.md):
- Page routes: slide-up + fade transitions
- Staggered list reveals (slide-up + fade) on home categories, top picks, saved list, categories grid
- Press feedback buttons (scale-down on tap)
- Hero image transitions between map pin → spot detail gallery

**Screens (all fully functional):**
- **Home** — greeting, "Explore the best places." headline, Trending hero card, category tiles, Top Picks Nearby rail
- **Map** — dark OSM map (no API key), circular photo pins with white rings, category badges, floating place card, white Get Directions pill, bookmark toggle
- **Spot detail** — hero photo gallery with pagination, ★ rating + review count, 3 fact tiles (Best Time/Best Spot/Great For), description, photo strip, sticky action bar
- **Saved** — photo rows with ratings, empty state
- **Profile** — avatar, handle, Visited/Saved/Collections stats, account rows
- **Submit** — 4-step flow: photo → details → pin drop → review/publish. Map picker has NO rotation (drag+zoom only). Photo upload from gallery.
- **Categories** — photo card grid, filter by tag

**Data layer:**
- 10 curated Lisbon seed spots with real ratings, review counts, best-time tags
- `SpotRepository` interface: `MockSpotRepository` (demo) / `SupabaseSpotRepository` (real)
- `supabase_schema.sql` — ready to run in Supabase SQL editor
- Photo upload to Supabase Storage (free tier)

**Tech:** Flutter 3.47, flutter_map + OSM tiles (free, no key), provider, supabase_flutter, image_picker, url_launcher

## Verification
- `flutter analyze` — clean
- `flutter test` — passing
- `flutter build web --release` — succeeds
- Live at http://192.168.1.18:8080/ (hard-refresh or incognito on phone)

## To connect Supabase (real data + auth + photo uploads)
1. Create free project at supabase.com
2. Run `supabase_schema.sql` in SQL editor
3. Create Storage bucket `photos` (public)
4. Get URL + anon key from Project Settings → API
5. Rebuild: `flutter build web --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`

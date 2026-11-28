# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Stack

Flutter 3.47 (single codebase: Android, iOS, web, macOS; one design language). Map: flutter_map + free Esri/OSM tiles (CARTO optional with a key). State: provider. Backend: repository pattern — `MockSpotRepository` seeded for demo mode; `SupabaseSpotRepository` (email auth, Postgres, storage, server-owned counters) when build-time keys exist. Distance sorting is client-side; there is no PostGIS dependency. No paid map, image, or API services — user constraint, confirmed.

## Users

- Photography enthusiasts looking for the best spots to shoot (viewpoints, golden-hour light, hidden gems).
- Travelers and locals exploring a city who want photogenic places worth visiting.

Primary situation: on the go, standing in a city, deciding where to shoot next; secondary: planning before going out.

## Product Purpose

A community-driven map of the best photo spots. Core v1 loop: browse map → open spot → view photos/details → save → submit a spot with photo. Success = discovering a spot worth visiting within seconds and feeling confident it's good.

## Positioning

Spots rise by algorithmic popularity (saves + freshness decay + recent views), not votes or editorial curation — the map itself shows you where the good light is, ranked by what the community actually saved.

## Operating Context

Mobile-first, used outdoors and while walking. Photos are the product's proof: every spot leads with imagery. Map tiles and photos load over the network; image URLs in seed data are synthetic placeholders (picsum) until real submissions exist.

## Capabilities and Constraints

- v1: map with viewport-culled photo pins (no clustering yet), spot detail (gallery, rank badge, tags, best-time), save/bookmark, saved list, three-step publish flow (photo → location → details), search + sort (near/top/most saved), algorithmic ranking.
- Free stack only (confirmed hard constraint).
- Location: real device location with a "when the user asks" permission model; a published photo's EXIF GPS places the pin automatically. The Lisbon seed is a fallback only when no fix has ever been cached.
- Accounts: Supabase email/password auth (the app never creates anonymous
  sessions); a build without keys runs a clearly labelled local-only demo
  profile.

## Brand Commitments

Working name "PhotoSpot" (builder-chosen, not user-ratified — open to rename). User's binding aesthetic feedback: the current near-black + amber glow / rounded-card treatment reads as generic "AI slop" and must not survive the redesign. Binding bar: **Apple-level polish** (restraint, precision, buttery motion).

## Evidence on Hand

- Working Flutter app in this repo; `flutter analyze` clean, 83 tests pass, web build succeeds, CI enforces both.
- 12 curated Lisbon seed spots with synthetic photos.
- No real user photos, testimonials, or usage data — nothing may claim them.

## Product Principles

1. The photo is the interface — imagery leads, chrome recedes.
2. Discovery must be immediate: a great spot is one tap from the map.
3. Ranking reflects real saves and freshness, never fake engagement.
4. Free-tier infrastructure only; no feature may require a paid service.
5. Every screen earns Apple-level restraint: precise, quiet, buttery.

## Accessibility & Inclusion

Not yet established; text contrast and touch targets (≥44pt) are standing requirements for the redesign.

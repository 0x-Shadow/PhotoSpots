# Surface brief: PhotoSpot app (all screens)

## Scope & mode
Operate. Mobile app (Flutter, iOS+Android), whole-app visual identity replacement.

## Audience, job, action
Photography enthusiasts + explorers finding the best photo spots. Job: discover → judge → save → go. Primary action: open a spot from map or list and save it.

## Proof / content
12 curated Lisbon seed spots with photos, ratings, distances, best-time tags. Synthetic data, labeled as demo.

## Constraints
Free stack only (flutter_map + OSM/CARTO). No paid APIs. User-pinned reference image governs the visual world.

## Chosen direction: user-pinned "findr." reference
User supplied a reference collage (findr. app) and pinned it: "make something like this." A user-pinned direction beats the roll; the dealt hand (photobook plate etc.) is discarded.

## Direction contract

THESIS: A photo-first dark discovery app where every surface is a full-bleed photograph and the UI is a quiet, precise frame around it — refusing the previous glow-and-glass look AND the flat paper look the roll dealt.

OWN-WORLD: Near-black ground (#0B0B0D), raised cards in #1A1A1E with 1px hairline borders, pure white display type at heavy weights with tight tracking, muted grey (#8E8E93) metadata, white pill buttons with black text as the single action color, photo-forward cards (image occupies 60-70% of card), circular icon buttons on dark glass, rating stars in warm amber. Inter for everything; hierarchy by weight and size contrast only.

STORY: Visitor lands on a photo, scans rating + distance + best-time at a glance, taps through to a detail page with hero photo and three quick-fact tiles, saves with one tap. Map shows photo-circle pins with category glyph badges; tapping a pin raises a floating place card.

FIRST VIEWPORT: Home = "Good morning," greeting, huge two-line headline "Explore the best places.", then a Trending photo card (full-width image, badge overlay, title+rating row, circular arrow), category icon tiles row, Top Picks Nearby horizontal rail, bottom tab bar (Home/Map/Saved/Profile).

FORM: findr. reference collage (user-pinned), mode operate; seed key 0f6aa110 (superseded by user pin).

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance.

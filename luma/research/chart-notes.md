# U.S. Top Free snapshot

Coverage target: 300 individually designed app icons, each tied to one package ID from one dated chart. This file records what was actually retrieved.

## Primary list

- Source: Google Play `topselling_free` cluster, country `us`, language `en`
- Tool: `google-play-scraper` 10.1.4 `list()`, requested count 300
- Fetched: 2026-10-26T01:00:44.724Z, which is Oct 25, 2026, 6:00:44 PM PT
- Returned: **199** unique package IDs, ranks 1–199 in that response
- Rank 1: Muse from Meta, `com.facebook.aura`
- Rank 199: Weather: Live Forecast & Radar, `com.sunny.weather.pinco`

The response stopped at 199 when 300 were requested. Ranks 200–300 are not in `us-top-free-snapshot.json`. They were not filled from memory, from a different chart, or by repeating apps.

## Cross-checks (not merged into the primary order)

**AppBrain** top free, all categories, United States.

- Pages: `https://www.appbrain.com/stats/google-play-rankings/top_free/all/us` and `/us/2`
- Page label: “Last updated: October 25, 2026” (no clock time on the page)
- Parsed rows: 196
- Ranks missing from the HTML: 29, 105, 134, 149
- Page `/us/3` repeated page 1 behind a paywall and was discarded

Of the 199 Play packages, 166 also appear in the parsed AppBrain rows. Only 9 share the same rank. The other 157 are the same package at a different rank. Example: both lists put Muse, ChatGPT, TikTok Pro, and Capital One in positions 1–4. Position 5 is Settings Home (`com.eet.settings.launcher`) on the Play pull and TikTok (`com.zhiliaoapp.musically`) on AppBrain.

**AppInsider** `https://appinsider.io/android/charts/us/all/free`

- Timestamp in the page: 2026-10-25T17:57:59+00:00, which is Oct 25, 2026, 10:57:59 AM PT
- 200 names in the visible table
- Package IDs in JSON-LD for the first 100 only
- 169 of those 200 names also appear somewhere in the 199-app Play list
- Only 7 of the first 100 JSON-LD package IDs sit at the same rank as the Play pull

The lists moved during the day, and the aggregators do not match each other. Artwork follows the primary Play pull only. A later pack should take a new snapshot rather than silently extending this one.

## What the 36 drawn icons cover

Ranks 1–36 of the 6:00 PM primary pull. Each drawable maps to one package ID. Neighboring short-drama apps use different silhouettes. A second color of the same symbol is not in the set.

## Logo set list (300)

A later pull, written to `us-top-free-300.json`.

- Fetched: 2026-10-26T01:34:42.442Z, which is Oct 25, 2026, 6:34 PM PT
- Tool: `google-play-scraper` 10.1.4, overall `topselling_free` plus US category Top Free lists from the same session
- Ranks 1–199: that overall response, in response order. Rank 1 is still Muse, `com.facebook.aura`. Rank 199 is onX Hunt, `onxmaps.hunt`. The 6:00 PM rank 199 (Weather: Live Forecast & Radar) had already moved.
- Ranks 200–300: the next 101 packages that were not in those 199, ordered by best category rank, then category name. Rank 200 is Gossip Harbor, `com.mergegames.gossipharbor`, category GAME rank 1. Rank 300 is Weather Forecast - Live Alerts, `com.weather.daily.local.live`, category WEATHER rank 10.

Play’s overall response still stopped at 199 when more apps were requested. Ranks 200–300 in this file are charting free apps. They are not published overall positions 200–300, and they were not invented to fill the gap.

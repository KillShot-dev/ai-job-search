# Luma — Icon Pack

Prototype of a paid Android icon pack for metaPhasic Group. The working product name is **Luma — Icon Pack**.

This directory is a separate product inside the workspace. It does not change the job-search tools.

## What is actually in this tree

| Piece | State |
| --- | --- |
| Logo set (the set wired into the app) | 300 single-glyph glossy squircles, `g001`–`g300` |
| Chart behind that set | 199 overall Top Free ranks, plus 101 category-chart apps. See `research/chart-notes.md` |
| Ink study | 36 earlier app icons and 16 system icons. Still in `artwork/`, not the dashboard |
| Launcher mapping files | Candidate components only. Not verified on a device |
| Dashboard | Branded HTML, also bundled for the WebView |
| Android Studio project | Source only. Not compiled, not signed |
| Google Play release | Not created |

`tracker/logo-summary.json` is the logo-set status. `tracker/summary.json` is the ink study. Artwork, mapping verification, and launcher testing stay in separate columns. Both tracks are `release_ready: false`.

## Rebuild

```bash
python3 luma/tools/build_logo_set.py   # needs /tmp/chart-extend.json
python3 luma/tools/validate.py
```

`build_logo_set.py` rewrites the logo-set SVG and PNG files, the dashboard, `appfilter.xml`, and the feature graphic. `build_icons.py` rebuilds only the ink study. Running it puts the ink dashboard back; run `build_logo_set.py` again to restore the logo set. It leaves `g001`–`g300` in `drawable-nodpi`.

PNG export uses `rsvg-convert`. Each logo tile must stay readable at 48×48, with a transparent corner and a unique glyph.

## Brand

`brand/metaphasic-group.png` is the metaPhasic Group lockup supplied for this pack. The dashboard header and the feature graphic use that file. The product name on the dashboard is Luma. The pack launcher mark (`ic_launcher`) is still the Luma crescent, not a redraw of the company logo.

# Luma — Icon Pack

Prototype of a paid Android icon pack for metaPhasic Group. The working product name is **Luma — Icon Pack**.

This directory is a separate product inside the workspace. It does not change the job-search tools.

## What is actually in this tree

| Piece | State |
| --- | --- |
| U.S. Top Free snapshot with package IDs | 199 apps recorded. Ranks 200–300 were not returned |
| Original app icons | 36 vector masters and transparent PNGs |
| System icons | 16, not counted toward the 300 |
| Launcher mapping files | Written. Not verified on a device |
| Dashboard | Local HTML, also bundled for a WebView |
| Android Studio project | Source only. Not compiled, not signed |
| Google Play release | Not created |

`tracker/summary.json` is the short status. `tracker/progress.csv` keeps artwork, mapping verification, and launcher testing in separate columns.

## Rebuild

```bash
python3 luma/tools/build_catalog.py   # needs the captured chart files
python3 luma/tools/build_icons.py     # rewrites SVG, PNG, XML, and the dashboard
python3 luma/tools/validate.py
```

`build_icons.py` overwrites `artwork/`. Edit glyph geometry in that script, or edit an SVG knowing the next rebuild will replace it.

PNG export uses `rsvg-convert`. The readability check rejects a glyph that is faint, tiny, or off-center at 48×48.

## Brand

The metaPhasic Group logo was not attached to this workspace. The dashboard keeps an empty labeled slot. Nothing in `brand/` or the dashboard is that logo.

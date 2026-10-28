# FileRadar icon system

Design standard: **rich, multi-layer glyphs** — not bare SF Symbol outlines. Every chrome view (Radar Glass, Preview Theater, Command Rail, Workspace Tabs) uses the same system.

## Principles

1. **Tile + depth** — gradient rounded tile, top sheen, soft colored shadow.
2. **Layered symbols** — primary fill glyph + secondary spark/detail symbol.
3. **Color hierarchy** — kind/place/nav each own a top→bottom palette; chrome accent tints selection and chrome-specific marks.
4. **Light & dark** — tiles use absolute hues that read on both appearances; sheen/stroke adapt via white opacity.
5. **Catalog vectors** — `Assets.xcassets/FRKind*.imageset` PDF templates for export / future polish; live UI prefers SwiftUI stacks in `FileRadarIcons.swift`.

## Families

| Family | Types | Swift |
| --- | --- | --- |
| File kinds | folder, image, video, audio, document, archive, app, other | `FRKindIcon` |
| Places | Desktop, Downloads, Documents, Pictures, Music, Movies, Home, Favorite, Pin | `FRPlaceIcon` |
| Navigation | Browser, Search, Cleanup, Sync, Shelves, Muse, … | `FRNavIcon` |
| Toolbar | Appearance, dual-pane, view mode, sort, inspector, more | `FRToolbarGlyph` |
| Chrome views | A–D glyphs with letter badge | `FRChromeGlyph` |
| Transfer / Drop Stack | Active pulse, tray+plus | `FRTransferIcon`, `FRDropStackIcon` |

## Asset catalog

| Asset | Role |
| --- | --- |
| `FRKindFolder` … `FRKindOther` | Vector PDF placeholders (preserves-vector-representation) |

## Where applied

- Sidebar / command rail labels  
- List rows & thumbnail fallbacks (`AsyncFileThumbnail`)  
- Drop Stack header + stacked file marks  
- Transfer HUD, Activities strip, top strip, docked drawer  
- Toolbar chrome / dual-pane / transfer controls  
- Sync pill between panes (Command Rail)  

## Implementation

- Source: `app/FileRadar/Views/FileRadarIcons.swift`  
- Sizes: `FRIconSize` — micro / toolbar / sidebar / list / hero  
- Chrome accent overrides AppLook while a chrome view is active  

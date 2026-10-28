# FileRadar — ForkLift-primary look (Mac + Windows)

**Owner:** Mac (this file). Windows matches these tokens and layout rules.  
**Date:** 2026-10-28 · **Sources:** ForkLift 4 public manual + marketing (BinaryNights), prior competitive notes.  
**Goal:** Default launch looks and feels like a dual-pane power file manager (ForkLift 4 patterns), not Showcase shelves Home.

Supersedes the *default composition* in `docs/fileradar-unified-look.md`. Shared chrome tokens (`FileRadarChrome`) still apply.

---

## 1. Default composition (ForkLift-primary)

Five chrome regions, one calm power-tool window:

1. **Compact sidebar** (~180–220 pt) — Favorites + Places first; Tools; More (Shelves Home demoted here). Drop Stack + disk bar at list bottom.
2. **Quiet toolbar** — appearance, dual-pane toggle, view (list/columns first), sort, inspector/Activities, transfers overflow.
3. **Dual-pane browsers** (center, default) — left | right folder lists with **path bars** above each pane; copy/move/sync between panes is primary.
4. **Activities strip** — always visible at the bottom of the detail; Pause / Resume / Cancel when working; Queue popover for per-item detail. Floating transfer HUD still appears when jobs are active/failed.
5. **Optional inspector** — closed by default on Browser; segmented Info | Activities when open.

Shelves Home, Search, Cleanup, Muse, Timeline, Disk Map remain secondary destinations — never the launch UI.

---

## 2. What we steal from ForkLift 4 (patterns, not trademarks)

| Pattern | FileRadar rule |
| --- | --- |
| Dual panes center-stage | Launch = Browser with Documents \| Downloads (or last tabs) |
| Path bar + status above each pane | Breadcrumb PathBar; item count on the trailing edge |
| Sidebar favorites / devices | Compact Favorites + Places; no huge Library wall |
| Activities / transfers controllable | Strip + HUD + queue; Pause / Resume / Cancel |
| Preview / Info secondary | Inspector optional; Activities is a first-class inspector mode |
| List / column density | Default view = **list**; columns first-class; grid/Showcase secondary |
| Sync between panes | Sync button → Compare Folders; copy/move toolbar + drag |
| Restrained materials | Frosted Modern chrome; no shelves marketing Home as default |

**Reject:** cloning ForkLift icons/branding; remote-connection density as default; Activities-only transfer UX; toolbar icon sprawl.

---

## 3. Layout rules (all platforms)

### 3.1 Launch

- Destination: **Browser** (dual-pane).
- Dual-pane: **on by default** (storage key may version-bump so old `false` does not stick).
- View mode: **list**.
- Inspector: **closed**.
- Shelves Home: sidebar under **More**, titled Shelves.

### 3.2 Dual-pane chrome

- Thin hairline divider between panes.
- Active pane: 1.5 pt accent stroke @ ~55% opacity + 3% accent wash.
- Path bar per pane: folder glyph, breadcrumb segments, item count; active pane accent underline.
- Quiet chrome bar above both panes: Copy → / Move →, Drop copies toggle, Sync.
- Drag between panes enqueues through the transfer queue (never silent overwrite).

### 3.3 Sidebar

| Section | Contents |
| --- | --- |
| Favorites | Browser, Search, Documents / Downloads / Desktop, starred favorites |
| Places | User pins |
| Tools | Clean Up, Duplicates, Compare, Workspaces |
| More | Shelves, Timeline, Disk Map, Muse, Extras, kind collections |

### 3.4 Transfer / Activities

When idle: strip shows `Activities · Idle` + Queue.  
When working or failed: strip shows progress + Pause/Resume/Cancel; floating capsule HUD bottom-center (max ~440 pt) with the same controls.

### 3.5 Density

| Surface | Density |
| --- | --- |
| Dual-pane / list | Comfortable orthodox: 8–12 pt row chrome |
| Shelves Home | Airy (unchanged) — secondary route only |
| Compact preference | Tighter sidebar + list; never required for Browser |

---

## 4. Design tokens

Reuse `FileRadarChrome` / `docs/fileradar-unified-look.md` §3 (accent `#007AFF`, materials, radii, type). No new purple/glow/cream themes.

Windows: match hex + radii + the layout rules above in the WinUI/theme layer; dual-pane Browser must be the default launch on Windows as well.

---

## 5. Evidence

| Artifact | Path |
| --- | --- |
| Mac screenshot | `media/fileradar-mac-forklift-home.png` |
| Windows screenshot | `media/fileradar-windows-forklift-home.png` (Windows agent) |
| Mac app | `~/Desktop/FileRadar/dist/FileRadar.app` |

---

## 6. Relationship to prior docs

- `docs/fileradar-unified-look.md` — tokens + materials still authoritative; **default composition** section is overridden by this file.
- `docs/fileradar-competitive-merge.md` — update mental model: ForkLift dual-pane is default; Bloom/Showcase shelves are secondary.

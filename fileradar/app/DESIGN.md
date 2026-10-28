# DESIGN.md — 10 principles → code

Source of the principles: `../files/design-awards-research.md` — 20
Apple-honored Mac apps (Apple Design Awards + App Store Awards Mac App of
the Year), verified 2026-10-26. **No award winner beyond that file is
claimed.** The mapping below is to concrete code locations in this
project, not to aspirations.

## 1. Native macOS controls, full keyboard navigation, standard shortcuts, menu bar extra

- `FileRadarApp.swift` — `MenuBarExtra`, standard `CommandMenu`s
  (View: Cmd+/Cmd- card size, Cmd-1/2/3/4 grid/list/columns/showcase;
  Go: Shift-Cmd-Space Quick Search), a real `Settings` scene. No iOS
  layout reused.
- `Views/ContentView.swift` — `NavigationSplitView` (the macOS sidebar
  pattern), `.inspector` pane, Cmd-Opt-I inspector shortcut.
- `Services/PlatformServices.swift` — AppKit where SwiftUI falls short:
  `QLPreviewPanel` (Quick Look), floating `NSPanel` (Quick Search),
  `NSEvent` global/local monitors (hotkey).
- `Views/FileViews.swift` — context menus, drag sources, keyboard
  focusability on cards.
- **Gap (honest):** global-hotkey reliability under sandbox + Input
  Monitoring permission is untested (see README UNTESTED).

## 2. One job per view (Home = shelves/recents, Search = results, Cleanup = decisions)

- `Views/ContentView.swift` — `Destination` enum; each destination renders
  exactly one view. No view does two jobs.
- `Views/HomeSearchViews.swift` — `HomeView` (shelves + recents +
  Downloaded-From groups) vs `SearchView` (query → chips → results).
- `Views/CleanupDuplicatesViews.swift` — `CleanupView` is decisions only
  (one card = one decision = one Trash action); `DuplicatesView` is
  keeper decisions only.
- `Views/BeatExtraViews.swift` — `TimelineView`, `DiskMapView`,
  `ExtrasView` are each a single job.

## 3. Content as interface: big thumbnails, large previews, hover inspector, Quick Look on Space; chrome shrinks

- `Views/FileViews.swift` — `FileCardView`: thumbnail fills the card,
  metadata is two small lines; hover reveals dimensions/duration/camera/
  source (the hover inspector summary).
- `Views/HomeSearchViews.swift` — `InspectorView`: full detail pane
  (dimensions, duration, camera, download source, tags with explanations,
  recognised text).
- `Views/ContentView.swift` — Space → Quick Look via
  `QuickLookHelper.shared.show(...)`.
- `Services/PlatformServices.swift` — `QuickLookHelper` (real system
  Quick Look panel, not a re-implemented viewer).
- **Gap:** thumbnails load synchronously (`NSImage(contentsOf:)`) — an
  async thumbnail cache is needed before release (README UNTESTED).

## 4. Direct manipulation: drag files out of menu bar, drag to Trash, drag between shelves, multi-file drag and drop; no dialogs for routine moves

- `Views/SystemViews.swift` — `MenuBarExtraView`: `.onDrag` with the file
  URL, so a download can be dragged straight out of the menu bar.
- `Views/FileViews.swift` — `FileCardView.onDrag`, `FileCollectionView`
  `.onDrop(of: [.fileURL])` (multi-file drop target).
- `Views/CleanupDuplicatesViews.swift` + `Services/TrashService.swift` —
  routine moves are Trash moves, not dialogs; dialogs appear only for
  **bulk** actions (confirm-first, principle 10), never for a single
  routine move.
- **Gap:** drag *between shelves* (re-shelving a file by dragging it onto
  another kind shelf) is not implemented as a distinct drop action —
  shelves are kind-derived, so a file's shelf follows its kind. Do not
  claim shelf-to-shelf dragging until a drop handler that reclassifies
  (or moves into a pinned folder) is built.

## 5. Motion that explains: filter chips animate in from search query; cleanup animations show where files went

- `Views/HomeSearchViews.swift` — `SearchView`: chips appear with
  `.transition(.move(edge: .leading).combined(with: .opacity))` inside
  `withAnimation(.easeOut)` on every query change.
- `Views/SystemViews.swift` — `QuickSearchPanelView`: same chip animation.
- `Views/CleanupDuplicatesViews.swift` — `CleanupView` completion state
  names the destination ("N files moved to Trash… restore them from
  Finder, or undo here") with an Undo button — the motion/explanation
  half is the message + undo, not a flying animation. A true
  fly-to-Trash animation is **not** implemented; the completion message
  is the honest substitute in this build.

## 6. Plain-language intelligence: search chips read like sentences; auto-tags explained in words; no AI branding noise

- `Models/SearchQuery.swift` — `SearchChip.sentence`, e.g. "Images from
  last week over 100 MB"; `ParsedQuery.sentence` shown above results.
- `Services/TagService.swift` — every auto-tag carries `explanation`
  ("Tagged Receipt because the text contains a total and a date.");
  `InspectorView` and `FileTag.accessibilityLabel` surface it.
- `Services/MoreServices.swift` — `ForecastService` results are labelled
  "a simple average, not a prediction" in `ExtrasView`.
- Nowhere in code or UI does the word "AI" describe a feature. Vision
  OCR is described as "recognised text", never branded.

## 7. One native look by default; optional palettes; System / Light / Dark

- `Models/Theme.swift` — **Modern** is the default Apple-native look
  (electric blue accent, `ultraThinMaterial`, continuous 12pt corners,
  SF Pro titles). Optional Elegant / Colourful / Minimal change palette
  only. `AppearanceMode` is System / Light / Dark — primary chrome.
- `Views/SystemViews.swift` — Settings **Appearance** (segmented) first;
  Look is optional secondary.
- `Views/HomeSearchViews.swift` — Home is shelves + recents + quiet rows
  (no look pills, no bento tiles). Toolbar cycles Appearance only.
- Layout, type scale, and `NavigationSplitView` navigation stay identical
  across looks — no per-look view variants.

## 8. Micro-delight: kind empty states, satisfying cleanup completion, Timeline view as discovery

- `Views/HomeSearchViews.swift` — `EmptyStateView`: every empty surface
  gets a kind, non-alarming message ("Nothing has been moved or
  deleted", "Nicely kept") instead of a blank list.
- `Views/CleanupDuplicatesViews.swift` — cleanup completion card with a
  checkmark, a count, and Undo.
- `Views/BeatExtraViews.swift` — `TimelineView`: month-grouped browsing
  so "when" is a discovery axis, not just a sort order.

## 9. Accessibility as design: full VoiceOver, Dynamic Type, high contrast, keyboard-only path for every action

- Implemented: `accessibilityLabel`/`accessibilityHint` on cards, chips,
  toolbar playback, treemap rows, and context-menu actions;
  `accessibilityElement(children: .combine)` on cards and empty states;
  keyboard shortcuts for view size, grid/list, inspector, Quick Look
  (Space), undo (Cmd-Z on completion), and Quick Search.
- Dynamic Type: views use the shared `FileRadarFont` system sizes, which
  respect the user's text-size setting; no fixed-size text blocks bypass
  it except treemap labels (caption size, still a system font).
- High contrast: colours are semantic (`.primary`, `.secondary`,
  `.accentColor`, system materials) rather than hardcoded RGB, so the
  system high-contrast appearance applies.
- **Gap (honest):** "full VoiceOver" and "keyboard-only path for every
  action" are design intents implemented at the control level, not
  verified by a VoiceOver pass or a keyboard-only audit on a Mac. That
  audit is required before release; bulk Trash confirmations and the
  licence sheet in particular need a keyboard-only check.

## 10. Trust through restraint: on-device only, nothing uploaded, destructive actions go to Trash never delete outright, undo everywhere, bulk actions confirm first, indexed search feels instant, background indexing/OCR never blocks UI

- `Services/Indexer.swift` — indexing on a detached task; search reads
  the in-memory index (`FileStore.search`).
- `Services/OCRService.swift`, `Services/DuplicateFinder.swift` —
  Vision work on background queues; iCloud-only files skipped everywhere
  (indexer flags them; OCR, hashing, and feature-printing all refuse
  them, so no download is ever triggered).
- `Services/TrashService.swift` — the only destructive path, via
  `FileManager.trashItem`; `undo`/`undoLastBatch` restore. No
  `removeItem` on a user file exists anywhere in the codebase
  (the only actual `removeItem(at:)` calls in the codebase are
  licence-state cleanup in `LicenseManager` and parcel staging cleanup
  in `ParcelExportService`; other `removeItem` mentions are comments
  stating this rule).
- `Views/CleanupDuplicatesViews.swift`, `Views/FileViews.swift` — bulk
  Trash actions (whole Cleanup card, all duplicates but keeper, any
  multi-file Trash) present a confirmation alert first.
- `Services/LicenseManager.swift` + README Licensing — no network call
  for licensing; activation state is local.
- `FileRadar.entitlements` — sandbox + user-selected read/write only;
  no network entitlement; Full Disk Access is user-granted in System
  Settings, documented in README.

## Iteration 1 — Finder-replacement features (2026-10-26)

Source of the features: `../files/finder-replacements-research.md` —
top 5 commercial Finder replacements (Path Finder, ForkLift 4,
Commander One PRO, QSpace Pro, Bloom). No competitor's icons, copy, or
layout is copied; only the feature ideas, re-expressed in FileRadar's
own UI. New code lives in `Services/IterationServices.swift` and
`Views/IterationViews.swift`, plus surgical edits to `ContentView`,
`FileViews`, `HomeSearchViews` (modular inspector), `Indexer` (sort
keys), `LicenseManager` (paid gating), `FileRadarApp` (menu), and
`SystemViews` (Settings toggle).

### 1. Native macOS controls, full keyboard navigation, standard shortcuts

- `Views/IterationViews.swift` — `CommandPaletteView` (Cmd-K, in the
  Actions menu and the toolbar): every palette action is also reachable
  from a menu or the toolbar, arrow keys move, Return runs, Escape
  closes. `TabBarView` is a native-styled tab strip with a keyboard-
  reachable New Tab (+) button.
- `Views/ContentView.swift` — Jump Panes (Ctrl-Tab) moves the
  active-pane highlight; Dual Pane toggle in the toolbar and Actions menu.
- **Gap (honest):** the tab strip is a SwiftUI strip inside the window,
  not macOS NSWindow tabbing; Jump Panes moves an active-pane highlight,
  not AppKit first-responder focus. Both need a Mac pass before they
  are described as system tabs / system focus.

### 2. One job per view

- `Views/IterationViews.swift` — `WorkspacesView` (save/restore layouts
  only), `SyncCompareView` (compare preview only), `ArchiveBrowserView`
  (read-only listing + extract-on-demand) are each one job, added as
  `Destination` cases in `ContentView` like every other view.
- `Views/ContentView.swift` — dual pane applies to folder-like
  destinations (kind, pinned) only; Home, Search, Cleanup and the rest
  keep their single-job views untouched.

### 3. Content as interface

- `Views/HomeSearchViews.swift` — `InspectorView` is now modular:
  Preview, Info, Tags, Permissions as collapsible modules in one
  inspector, with all previous detail content kept (dimensions,
  duration, camera, download source, tags with explanations, recognised
  text with paid-gated copy-all). Permissions is read-only display.
- **Gap:** permission *editing* is not built; the inspector honestly
  says so.

### 4. Direct manipulation

- `Views/IterationViews.swift` — `DropStackView`: a temporary holding
  tray in the sidebar; drag files onto it, place the whole stack in a
  chosen folder (or drag single files back out). Session-only by
  design — a stack is a momentary handful, not a collection.
- `Views/ContentView.swift` + `Views/FileViews.swift` — dual-pane
  drag-between: dropping files on the second pane enqueues a move
  through the transfer queue; a name clash is skipped and reported,
  never overwritten.
- `Services/IterationServices.swift` — `DropUtilities` gives the tray
  and the panes one shared drop behaviour.

### 5. Motion that explains

- No new animation is claimed. The transfer queue's per-file progress
  and the Drop Stack's targeted highlight are the explanation for bulk
  work; a fly-to-destination animation is **not** implemented.

### 6. Plain-language intelligence

- `Views/IterationViews.swift` — queue and compare copy stays in plain
  words ("Move 3 files to Photos", "Only on the left"), and the sync
  preview explains itself before anything moves. No AI branding anywhere.

### 7. Two looks from one system

- Iteration 1 views use only `FileRadarFont`, semantic colours, and
  system materials, so both looks and light/dark apply unchanged. No
  per-look view variants were added.

### 8. Micro-delight

- `Views/IterationViews.swift` — kind empty states for the stack, the
  queue, workspaces, archives, and matching folders ("Folders match"),
  in the existing `EmptyStateView` voice.

### 9. Accessibility as design

- Palette, tabs, stack, queue, and compare controls carry
  accessibility labels/hints; every palette action has a menu/toolbar
  equivalent. **Gap (honest):** as with the original audit gap, no
  VoiceOver or keyboard-only pass has been run on a Mac for these views.

### 10. Trust through restraint

- `Services/IterationServices.swift` — `TransferQueue`: one visible
  queue, progress, pause, cancel; bulk work runs off the main thread.
  Pause/cancel take effect *between* files, not mid-file (a single
  file's copy/move is synchronous) — stated in code and README, not
  smoothed over.
- `Services/IterationServices.swift` — `SyncCompareService`: preview
  only; the sole destructive action is moving previewed left-only files
  to Trash via `TrashService`, after a confirmation alert. No automatic
  sync, no outright delete.
- `Services/IterationServices.swift` — `ArchiveBrowser`: read-only
  listing; extraction only on demand to a user-chosen folder; nothing
  inside an archive is modified in place.
- `Services/IterationServices.swift` — `GitStatusService`: read-only,
  opt-in (Settings, off by default); never stages, commits, or resets.
- `Services/IterationServices.swift` — `FolderSizeService`: sizes
  computed in the background and cached; iCloud-only files are never
  downloaded to be measured.
- `Services/LicenseManager.swift` — paid gating, same pattern as
  before: dual-pane, tabs, Drop Stack, folder sizes, modular
  inspector, and command palette are CORE; folder sync/compare,
  archive browse, and workspaces are PAID (`folderSyncCompare`,
  `archiveBrowse`, `workspaces`), each showing `LockedFeatureView`.
- **Deliberately left out:** remote locations (WebDAV/SFTP read-only
  browse). It would need a network entitlement — which this build
  forbids — plus an SFTP library that is not in the standard library.
  Leaving it out cleanly beats shipping a half-working remote browser
  that weakens the on-device promise.

## Iteration 3 — competitive premium polish (2026-10-27)

Against ForkLift / Path Finder / Commander One / QSpace / Bloom (see
`docs/fileradar-competitive-analysis.md`). Still no remotes; still optional
dual-pane.

- `Views/IterationViews.swift` — Transfer HUD (ForkLift feel), per-item
  cancel, dual-pane right-folder picker + copy-on-drop, tab chrome.
- `Views/ShipReadyViews.swift` — selection Batch Rename sheet; preview strip.
- `Views/FileViews.swift` — drop-zone wash, Drop Stack / rename in menus.
- `Views/ContentView.swift` + `FileRadarApp.swift` — Space multi-QL,
  Shift-Cmd-R / Shift-Cmd-P / Cmd-Delete / Cmd-A wired.
- `Models/Theme.swift` — quiet atmosphere wash (not flat, not glow).

## Iteration 2 — ship-ready polish (2026-10-27)

Focus: beauty + sellability + MAS/direct monetization, not feature spam.

### Beauty / density
- `Models/Theme.swift` — copper accent (Colourful), compact density
  toggle, rounded title scale, shared `FileRadarMotion` curves.
- `Views/FileViews.swift` — async `ThumbnailCache` cards, hover wash,
  favorite star, column mode in `FileCollectionView`.
- `Views/ShipReadyViews.swift` — Miller-style `ColumnBrowserView`.

### Competitive features that fit
- Favorites sidebar + toggle in context menu (`FavoritesStore`).
- Manual coloured tags in the inspector (`ManualTagStore`); search
  matches them via `FileStore.manualTagNames`.
- Saved searches (paid) from Search + sidebar (`SavedSearchStore`).
- Parcel export wired in Extras, context menu, and Actions menu.
- Cmd-3 column view.

### Trust / monetization
- `StoreKitLicense` (StoreKit 2) + `TrialManager` (14-day Keychain) +
  `LicenseServerClient` (optional HTTPS) fold into `LicenseManager`
  unlock sources: serial | storeKit | trial.
- `LicenseEntryView` forks MAS vs direct; secrets stay out of the client.
- Debug entitlements now include the same Muse network/mic/speech keys
  as Release (plus get-task-allow).

# FileRadar — macOS app source

FileRadar is a Finder alternative for Mac from **metaPhasic Group**: shelves
by file kind, plain-language search, on-device text recognition, downloads
grouped by source, duplicates, and Trash-only cleanup — plus original
extras (Smart Collections, Timeline, disk map, version stacks, batch
rename, auto-tags, storage forecast, file-health checks, parcel export).
It works **alongside Finder**; it does not replace it.

## Ship-ready iteration (this branch)

Added without claiming a Mac compile: async thumbnails, column browser,
favorites, manual tags, saved searches, parcel export UI, StoreKit 2 +
14-day Keychain trial + optional HTTPS license activate/validate,
Debug entitlements aligned with Muse, shared Xcode scheme, Assets catalog.
Distribution keys in `Info.plist`: `FRDistribution`, `FRStoreKitProductID`,
`FRLicensingBaseURL` (public values only). See repo root `README.md` and
Project store docs `fileradar-review.md` / `fileradar-ship-checklist.md`.

- Bundle ID: `com.metaphasicgroup.fileradar`
- Platform: macOS 14+, Apple silicon + Intel (universal build in Xcode)
- Language: SwiftUI, with AppKit where SwiftUI falls short (Quick Look
  panel, menu-bar drag-out, floating Quick Search panel, global hotkey)
- Support contact (the only contact in this codebase): `support@metaphasic.net`
- Privacy: **no account, nothing uploaded, on-device only.** iCloud-only
  files are listed but never downloaded. No analytics, no network calls
  for licensing in this build (see Licensing below).

> **Honest status — read this first.** This source was written on a Linux
> VM with no Xcode and no macOS. It has **not been compiled, run, or
> tested on a Mac**. See [UNTESTED](#untested--what-could-not-be-verified)
> for exactly what is unverified. Do not ship this without building it in
> Xcode and fixing whatever the compiler and manual testing surface.

## Feature checklist (mapped to the 10 design principles)

Design authority: `../files/design-awards-research.md` — 20 Apple-honored
Mac apps (Apple Design Awards + App Store Awards Mac App of the Year),
verified 2026-10-26. No award winner beyond that file is claimed anywhere
in this codebase. The principle-by-principle code map is in `DESIGN.md`.

| Feature | Status in this code | Principle |
| --- | --- | --- |
| Shelves by kind (Images, Videos, Music, Documents, Archives, Apps) with big thumbnails | Implemented (`HomeView`, `FileCardView`) | 3 |
| Natural-language search → visible filter chips (type/date/size/source) over filenames, tags, file text | Implemented, rule-based parser (`SearchQuery.swift`, `SearchView`) | 5, 6 |
| On-device OCR text-in-images via Vision; OCR in PDFs | Implemented (`OCRService`, `PDFShim`); **Copy all recognised text is paid-gated** (`InspectorView`) | 6, 10 |
| "Downloaded From" grouping (Gmail, Google Drive, ChatGPT, Canva, X, Slack, WhatsApp, GitHub, extensions, any website) | Implemented via quarantine + WhereFroms xattrs (`DownloadSourceDetector`); unknown hosts become `website(host)` | 6 |
| Duplicates: SHA-256 identical + Vision feature-print look-alikes; keeper picked, rest to Trash; iCloud-only skipped | Implemented (`DuplicateFinder`, `DuplicatesView`); **paid-gated** | 10 |
| Clean Up cards: old installers, forgotten downloads, old screenshots, big old videos, unused apps — Trash only | Implemented (`CleanupEngine`, `CleanupView`); **paid-gated**, bulk action confirms first | 2, 10 |
| Quick Search global panel (Shift-Cmd-Space, configurable shortcut) | Panel + in-app shortcut implemented; global monitor implemented (`HotkeyService`, `QuickSearchPanelView`); **paid-gated** (panel shows no results in demo) | 1 |
| Menu bar: last-10 downloads with thumbnails + drag out | Implemented (`MenuBarExtraView`); **paid-gated extras** | 1, 4 |
| Two looks (colourful / black-white-grey minimal) + light/dark | Implemented (`ThemeSettings`, Settings) | 7 |
| Home dashboard; library sidebar (Recents, kinds, Smart Folders for Large Files and Screenshots, pinned folders) | Implemented (`ContentView`, `HomeView`) | 2 |
| Grid/list views, card size Cmd+/Cmd-, sort by name/date/size/kind; Quick Look on Space; in-toolbar music playback; inspector (dimensions, duration, camera, download source) | Implemented (`ContentView`, `FileViews`, `InspectorView`, `MusicPlaybackService`) | 1, 3 |
| Full right-click actions (Quick Look, Open, Show in Finder, Pin to Sidebar, Copy, Copy Path, Move to Trash); multi-file drag and drop | Implemented (`fileContextMenu`, drag in `FileCardView`/`MenuBarExtraView`, drop in `FileCollectionView`) | 4 |
| Shortcuts/Siri actions (Find Files, Get Latest Download); saved searches; automatic clean-up rules OFF by default | Intents + provider implemented (`PlatformServices`); rules OFF by default (`MoreServices`, Settings). **Saved searches are NOT yet implemented** — see UNTESTED. Shortcuts/Siri are **paid-gated** by policy (see note below) | 1 |
| Background auto-updates (Sparkle-style, documented, not wired to a live feed) | Documented stub only (`UpdateService.feedURL = nil`); no Sparkle bundled, no feed contacted | 10 |
| Privacy: no account, nothing uploaded, on-device only, iCloud-only never downloaded, works alongside Finder | Implemented by design (indexer/OCR/duplicates all skip iCloud-only files) | 10 |
| **Beat-extras, all on-device** | | |
| Smart Collections (receipts/invoices, unfinished drafts, screenshots-with-text, auto-sorted) | Implemented (`TagService.smartCollections`, Home + sidebar) | 6, 8 |
| Timeline view | Implemented (`TimelineView`) | 8 |
| Disk map (treemap) | Implemented, one-level proportional layout (`DiskMapView`, `TreemapView`) — a full recursive squarified treemap is a future refinement | 8 |
| Version stacks (v1/v2/final grouping) | Implemented (`VersionStackService`, `ExtrasView`) | 2 |
| Batch rename with patterns (`{name}`, `{n}`, `{date}`) | Implemented, collisions refused (`RenameService`, `ExtrasView`); **paid-gated** | 4 |
| Auto-tags plus manual coloured tags | Auto-tags implemented with plain-language explanations (`TagService`); manual tag editing UI is **not yet implemented** — tags are currently auto-assigned only | 6 |
| Storage forecast | Implemented, labelled as an estimate (`ForecastService`) | 6 |
| File-health checks (zero-byte/corrupt/legacy formats) | Zero-byte + legacy-format implemented; **corrupt-file detection is heuristic-only** — a file that fails to read is not currently flagged as corrupt (see UNTESTED) | 10 |
| "Parcel" export (zip a selection + manifest) | Implemented via `/usr/bin/zip` (`ParcelExportService`); **paid-gated**; no UI button wires it yet — see UNTESTED | 4 |
| **Iteration 1 — Finder-replacement features (2026-10-26, uncompiled — see UNTESTED)** | | |
| Dual-pane mode, optional and off by default; drag files between panes; Jump Panes (Ctrl-Tab) | Implemented for folder views (`DualPaneView`, `ContentView`); default stays shelves + search | 1, 2, 4 |
| Drop Stack: temporary holding tray in the sidebar | Implemented, session-only (`DropStackView`) | 4 |
| Transfer queue: one visible queue for every copy/move, with progress, pause, cancel; bulk work off the main thread | Implemented (`TransferQueue`); pause/cancel act between files, not mid-file | 10 |
| Native-styled tabs for multiple locations, restored on relaunch | Implemented as an in-window tab strip (`TabState`, UserDefaults); **not** macOS NSWindow tabbing — see UNTESTED | 1 |
| Saved workspaces: named layouts restoring tabs, panes, pinned folders | Implemented (`WorkspacesView`); **paid-gated** | 2 |
| On-demand folder sizes in the background + expanded sort keys (size, kind, date added, name, date modified) | Implemented (`FolderSizeService`, list rows; `FileStore.sorted`) | 10 |
| Modular inspector: Preview, Info, Tags, Permissions as collapsible modules | Implemented, previous detail content kept (`InspectorView`); Permissions is read-only display | 3 |
| Archive browsing as folders: ZIP/TAR read-only listing, extract only on demand | Implemented (`ArchiveBrowserView`); **paid-gated**; entry-level open not built — see UNTESTED | 3 |
| Command palette (Cmd-K) for every action, full keyboard navigation | Implemented (`CommandPaletteView`, Actions menu + toolbar) | 1, 9 |
| Folder sync/compare with preview and Trash-only deletions (P1 stretch) | Implemented, preview only (`SyncCompareView`); **paid-gated**; deletions only via TrashService after confirmation | 10 |
| Git status badges, read-only and opt-in (P1 stretch) | Implemented, off by default (`GitStatusService`, inspector module, Settings toggle) | 10 |
| Remote locations (WebDAV/SFTP read-only browse, P1 stretch) | **Not built** — would need a network entitlement (forbidden in this build) and an SFTP library; left out cleanly | 10 |

**Paid-gating note on Shortcuts/Siri:** the intents themselves do not
consult `LicenseManager` at run time (AppIntents run out-of-process and
cannot read the app's licence state reliably in this design). The gating
is by policy and by result: `FindFilesIntent` returns a pointer to open
the app rather than file contents, and full in-app intent wiring is listed
in UNTESTED. Do not describe Shortcuts as "fully paid-gated in code"
until that wiring is built and tested.

**Demo vs full version.** Demo mode: browse, search, preview only.
Paid features (see `PaidFeature` in `Services/LicenseManager.swift`):
OCR copy-all, Duplicates, Clean Up, Quick Search panel, menu-bar extras,
Shortcuts/Siri, saved searches, automatic clean-up rules, batch rename,
parcel export, Smart Collections, **plus iteration 1: folder sync &
compare, archive browsing, workspaces**. Core in iteration 1 (available
in demo): dual-pane mode, tabs, Drop Stack, folder sizes, modular
inspector, command palette. Every locked surface shows a plain
`LockedFeatureView` with the same message — no dark patterns, no timers.

## Muse chat (2026-10-27, uncompiled — see UNTESTED)

FileRadar includes a Muse-powered chat UI: a sidebar destination
"Muse" (`Views/MuseChatViews.swift`) with streaming replies, a composer,
a stop button, local conversation history, tool-call Approve/Deny cards,
a "Share current folder" toggle (default OFF), and voice input/output.
The demo shows the same panel in its not-connected state plus a labeled
guided tour; the site adds three Muse cards. Read this section before
describing Muse chat anywhere — several limits are easy to overstate.

**What it is, honestly.** This is NOT the embedded Muse personal-agent
runtime, and it is NOT a verified official login to a personal Muse
account — no public third-party OAuth flow for that could be verified.
It is a chat client powered by Muse Spark through Meta's
OpenAI-compatible Model API, with FileRadar tools executed locally on
the Mac. **FileRadar is not affiliated with or endorsed by Meta.**
A user's personal Muse app history and memory do **not** carry over
into FileRadar.

**Configuration (a developer step, before shipping).** Copy
`MuseConfig.sample.plist` to `MuseConfig.plist` and fill in the base
URL, client ID, redirect URI, scopes, and model ID from the Meta
developer dashboard — and verify them there. The sample contains
placeholders only and fails closed: a missing file, missing key,
leftover placeholder, or non-HTTPS base URL throws `notConfigured`
and nothing ever silently connects. The values
`https://api.meta.ai/v1` and `muse-spark-1.3` appear ONLY in comments
as third-party-reported defaults labeled "verify in your Meta developer
dashboard" — never as active defaults, never as Meta-confirmed facts.
There are no keys, endpoints, or endorsements invented anywhere here.

**Login (extremely secure, by design).** `ASWebAuthenticationSession`
+ PKCE (S256) + fresh random state + nonce per attempt; URL scheme
`fileradar` (`CFBundleURLTypes` in `Info.plist` — verify in Xcode
target > Info > URL Types). Tokens live ONLY in the Keychain (service
`com.metaphasicgroup.fileradar.muse`, biometric access control:
biometry current set, this-device-only, never synced), following the
license-serial Keychain pattern: short-lived access token + rotating
refresh token, refresh when under 60s of life remains, fail-closed wipe
on refresh failure. Logout wipes all Muse tokens; deleting chat history
is a separate explicit button and never happens silently on logout.
HTTPS only; no App Transport Security exceptions; generic errors only;
no tokens in UserDefaults, logs, or analytics.

**Chat + local tools.** Streaming SSE chat completions
(`tool_choice: "auto"`, up to 5 tool rounds). Tools execute LOCALLY,
never in the cloud: `searchFiles`, `listShelf`, `getFileInfo`,
`previewFile` (metadata only), `trashFiles`, `moveFiles`,
`cleanUpPreview`, `duplicatesPreview`, `showInFileRadar`, `openFile`.
Trash, move, and open require in-UI Approve before anything happens;
read-only tools run automatically and appear in the transcript.
**File contents are never sent to any server:** tool outputs contain
names, metadata, and summaries only — no full paths, no contents, no
OCR text. Proactive folder context is sent ONLY when the "Share current
folder" toggle is ON (default OFF), and then only the current view's
title plus up to 50 file names. Cleanup/duplicates previews require a
paid licence (locked message otherwise); there is no cleanup-apply tool.

**Voice.** `SFSpeechRecognizer` (on-device recognition preferred where
available; system fallback otherwise — no FileRadar transcription
endpoint exists), push-to-talk plus a hands-free toggle,
`AVSpeechSynthesizer` spoken replies, a visible "Listening…" indicator,
and transcripts sent as messages through the same tool layer as typed
text (e.g. "find screenshots from last week" runs `searchFiles`).
Audio is never stored (in-memory buffers only). Voice needs the
`NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription`
strings in `Info.plist` (present) plus the entitlements below.

**Entitlements added for Muse.** `com.apple.security.network.client`
(HTTPS only, Model API), `com.apple.security.device.audio-input`
(microphone), and `com.apple.security.device.speech-recognition`.
⚠️ **The speech-recognition key is UNVERIFIED** — it was added with an
explicit `VERIFY-IN-XCODE` comment because sources conflict on whether
Speech needs a sandbox entitlement at all. If Xcode/codesign rejects
it, delete it and rely on the usage-description string alone; do not
present it as Apple-verified until that check passes. Everything else
stays least-privilege: the Debug/Release split is unchanged and
`get-task-allow` remains Debug-only.

**Privacy when connected.** Chat messages and tool outputs
(names/metadata) go to the configured Model API endpoint — that is the
feature working as intended. File contents, OCR text, and full paths
are never sent. When not connected, nothing leaves the Mac and the
pre-Muse privacy posture (no account, on-device only) stands.

## Licensing (real code, local only)

- Serial format: `FR-XXXX-XXXX-XXXX-XXXX`. Alphabet excludes confusing
  characters (no `0`/`O`, `1`/`I`/`L`): `ABCDEFGHJKMNPQRSTUVWXYZ23456789`.
- Checksum (identical to the licensing backend, `../licensing/serials.py`,
  the authoritative spec): the first 15 characters are the payload and
  the 16th character is `alphabet[sum((i+1) * index(payload[i])) mod 31]`.
  `LicenseManager.validate` recomputes it, so a made-up serial fails
  unless its checksum character happens to match (1-in-31 per guess).
  Local validation is a typo check only, not proof of purchase.
- Activation state is stored locally only, in the macOS Keychain
  (generic-password item, never synced). Builds before the 2026-10-27
  hardening pass stored the serial in UserDefaults + a JSON file in
  Application Support; on first launch the app migrates any such serial
  into the Keychain and deletes both legacy copies. Deactivate deletes
  the Keychain item, so the serial moves to another Mac.
- **No server is contacted for licensing in this build.** Server-side
  validation exists in the licensing backend (`validate-serial` endpoint,
  checking the serial exists in its database) and uses the same checksum
  algorithm (`licensing/serials.py` is the authoritative spec), but the
  app does not call it yet. Do not claim the app performs server
  validation until that wiring is built and tested.
- Never hardcode credentials anywhere in this codebase. There are none.

## Project layout

```
FileRadar.xcodeproj/            Hand-written Xcode project (see note below)
FileRadar/
  FileRadarApp.swift            App entry, MenuBarExtra, CommandMenus, Settings scene
  Info.plist                    Bundle ID, macOS 14 minimum, no network keys
  FileRadar.entitlements        Release entitlements: App Sandbox +
                                user-selected read/write + Downloads
                                (NO get-task-allow, NO network)
  FileRadar.Debug.entitlements  Debug-only entitlements (adds
                                get-task-allow); Debug config only
  Models/
    FileItem.swift              FileItem, FileKind, DownloadSource, FileTag
    SearchQuery.swift           Natural-language → filter chips parser
    Theme.swift                 Two looks, one type scale
    CleanupModels.swift         Cleanup cards, duplicate groups, version stacks, health, disk nodes
  Services/
    Indexer.swift               Background file index + FileStore (search, shelves, recents)
    OCRService.swift            Vision text recognition (images + PDFs)
    PDFShim.swift               PDFKit rasteriser for OCR
    DuplicateFinder.swift       SHA-256 + Vision feature-print duplicates
    DownloadSourceDetector.swift Quarantine / WhereFroms xattr source detection
    TagService.swift            Auto-tags + Smart Collections
    TrashService.swift          Trash-only moves + undo
    MoreServices.swift          Cleanup engine/rules, rename, parcel export, health,
                                forecast, version stacks, music playback
    LicenseManager.swift        Real checksum validation + local activation
    PlatformServices.swift      Quick Look panel, hotkey service, Quick Search panel,
                                AppIntents, inert update stub (no network call)
  Views/
    ContentView.swift           NavigationSplitView shell, sidebar, inspector, shortcuts
    FileViews.swift             File cards, grid/list, context menu, drag/drop
    HomeSearchViews.swift       Home, Search (chips), empty states, Inspector
    CleanupDuplicatesViews.swift Clean Up, Duplicates, locked-feature screen
    BeatExtraViews.swift        Timeline, Disk Map, Extras (rename/forecast/health/stacks)
    SystemViews.swift           Menu bar extra, Quick Search panel, licence entry, Settings
```

## Build steps (Xcode, on a Mac)

1. Open `FileRadar.xcodeproj` in Xcode 15+ on macOS 14+.
2. **First open: verify the project.** The `.pbxproj` was hand-written
   on Linux (Xcode was unavailable), not generated by Xcode. If Xcode
   reports a project error, create a fresh macOS App project in Xcode
   (SwiftUI, bundle ID `com.metaphasicgroup.fileradar`) and add the
   `FileRadar/` source files to it — the code is organised to drop in.
   Either way, confirm every `.swift` file is in the target's
   **Build Phases → Compile Sources**, and Vision, QuickLookUI, PDFKit,
   AVFoundation are in **Link Binary With Libraries**.
3. Set your Development Team in **Signing & Capabilities**. The project
   uses Automatic signing; the entitlements file enables the App Sandbox
   with user-selected read/write (see Entitlements note below).
4. Add an App Icon: create `Assets.xcassets` with an `AppIcon` set
   (none is shipped in this source — the project references the name
   `AppIcon` only in the deleted build-setting sense; Xcode will warn
   until an asset catalog exists). Do not ship with a placeholder icon.
5. Build and run: **Product → Run** (⌘R), or from Terminal:
   ```sh
   xcodebuild -project FileRadar.xcodeproj -scheme FileRadar -configuration Debug build
   ```
   Note: no scheme file is shipped (schemes are normally generated by
   Xcode on first open and are user-specific). If `xcodebuild` reports
   "no scheme", open the project in Xcode once, let it create the scheme,
   then retry.
6. Grant permissions on first run as macOS prompts: file access for the
   folders you index, and Input Monitoring/Accessibility if you want the
   global Shift-Cmd-Space hotkey while another app is frontmost.

### Entitlements / Full Disk Access — read this

- The entitlements file requests the **App Sandbox** and
  **user-selected read/write** (plus Downloads read/write). That is the
  correct, reviewable posture for a file utility.
- **Full Disk Access is not an entitlement.** It is granted by the user
  in System Settings → Privacy & Security → Full Disk Access, by adding
  FileRadar there. Without it, FileRadar can only index folders the user
  has explicitly granted (picked in-app / Downloads, Documents, Desktop
  as prompted). Document this in the user-facing help before release;
  do not promise "sees every file" without that grant.
- Sandboxed apps cannot read other apps' containers or Mail data
  directly. "Downloaded From: Gmail" here means *files downloaded from
  Gmail's web interface* (via WhereFroms/quarantine), not reading the
  Mail app's store. Do not overclaim this.

## Security posture (hardening pass, 2026-10-27 — static only, uncompiled)

Nothing here is a penetration test or an audit certification: this code
has never been compiled or run on a Mac. What follows is what the code
is designed to do, and what a Mac build pass must still prove.

- **Serial storage: Keychain only.** `LicenseManager` stores the
  activation serial as a Keychain generic-password item
  (`com.metaphasicgroup.fileradar.license` / `activation-serial`,
  accessible-when-unlocked, no access group, never synced). First launch
  migrates a legacy UserDefaults/JSON serial into the Keychain and
  deletes both legacy copies. Keychain failures fail closed (locked, no
  crash) and no error path ever includes the serial. UserDefaults still
  holds only non-secrets: theme, tabs, workspaces, folder URLs.
- **Entitlements: least privilege, Release cannot carry get-task-allow.**
  Release (`FileRadar.entitlements`): App Sandbox, user-selected
  read/write, Downloads read-write — and nothing else. The debug
  entitlement `com.apple.security.get-task-allow` is ABSENT from the
  Release file (an earlier draft listed it as `false`; absence is what
  reviewers check for). Debug builds use `FileRadar.Debug.entitlements`
  (same keys + `get-task-allow = true`), wired only to the Debug
  configuration, and a build-phase guard ("Guard: Release must not carry
  get-task-allow") fails any Release build whose entitlements contain
  the key set to true. ⚠️ **Before any Archive/distribution, verify by
  hand** (the guard only checks the Release entitlements file, not the
  final signed product):
  ```sh
  codesign -d --entitlements :- FileRadar.app | grep -c get-task-allow  # must print 0
  ```
  Never ship a build made from the Debug configuration.
- **Network: none, except Muse chat (added 2026-10-27).** Before Muse,
  there was no `com.apple.security.network.client` entitlement and no
  live network API in the app. Muse chat adds that entitlement
  (HTTPS only, for the developer-configured Model API endpoint — see
  "Muse chat" above); licensing/activation paths still make no network
  calls. `UpdateService.checkForUpdates()` is inert and always
  reports updates unconfigured (an earlier draft fetched a feed when a
  URL was set; that call was removed). Enabling updates later requires
  a coordinator decision plus Sparkle, a network entitlement, and a
  signed appcast — not a one-line edit. `NSWorkspace.open` for the
  support `mailto:` link opens Mail; it is not a network call by this app.
- **Trash-only deletion.** User files are NEVER deleted outright: every
  destructive path goes through `TrashService` (`trashItem`, with undo
  restoring from Trash). The only `removeItem` calls in the codebase are
  (a) deleting the legacy licence-state file and (b) cleaning up
  FileRadar's own parcel-staging and archive-extraction-staging
  directories. Grep for `removeItem` on every change and keep it that way.
- **Archive extraction: staged, confined, quarantine-preserving.**
  `ArchiveBrowser.extract` never extracts straight into the user's
  folder: it validates every entry name (rejects absolute paths and
  `..` escapes; refuses to extract if the listing cannot be read), then
  extracts to a fresh temporary staging directory, walks the staged tree
  resolving every symlink, and rejects the whole extraction — staging
  removed, folder untouched — if anything resolves outside staging
  (symlink policy: REJECT, never follow). Only then are staged items
  moved in, and only if no same-named file already exists there
  (never-overwrite, matching transfers/renames). If the archive itself
  is quarantined, extracted regular files are stamped with the same
  quarantine value, so downloads do not silently lose Gatekeeper
  protection. Quarantine is never stripped anywhere: the detector only
  reads xattrs, and no file is ever executed automatically — opening is
  always the user's explicit Open action.
- **Copy/move/rename confinement.** Transfers move by rename and skip
  symlinked files on copy (never dereference-and-duplicate a link
  target); the indexer, folder-size walk, and sync-compare walk never
  follow symlinks (and skip descending into symlinked directories).
  Parcel export skips symlinks and duplicate staging names, so its
  manifest never claims a file the zip does not contain. Rename patterns
  are sanitized (`/` and `\` become `-`; `.`, `..`, empty refused) and
  `apply` re-checks the destination is in the file's own folder, so a
  pattern like `../escaped` cannot move a file out of its folder.
- **Logging: none that leaks.** There are no `print`/`NSLog`/`os_log`
  calls in the app. Error strings shown to the user name files by
  last-path-component only, and extraction errors are deliberately
  generic (they never echo archive entry names or full paths).
- **Sandbox sufficiency for Downloads/Documents/Desktop (design, NOT
  yet proven).** Downloads is covered by the Downloads read-write
  entitlement; Documents and Desktop are reached only through
  user-selected read/write, i.e. the user must pick those folders
  in-app (the default tab set offers Downloads/Documents, but Documents
  indexing before the user grants it will simply find nothing — that
  behaviour is the first thing the Mac pass must check; see UNTESTED).
  Do NOT add a Documents/Desktop entitlement or full-disk access to
  "fix" a prompt: the prompt is the sandbox working. Full Disk Access
  remains a user-granted System Settings permission, never an
  entitlement.

### What a Mac build pass must still verify (security)

1. Xcode build succeeds for both configurations, and the Release
   product's `codesign` entitlements contain no `get-task-allow` and no
   network entitlement (command above; also check the Debug product
   does carry `get-task-allow`, proving the split is wired correctly).
2. Keychain round-trip: activate → quit → relaunch stays unlocked;
   deactivate → relaunch stays locked; upgrade path: a pre-hardening
   build's UserDefaults/JSON serial migrates once and both legacy
   copies disappear (check `~/Library/Application Support/FileRadar/
   license.json` is gone and the UserDefaults key is unset). If the app
   is re-signed under a different identity, expect the old Keychain
   item to become inaccessible and the user to re-enter the serial —
   that is the safe fallback, not a bug to "fix" by weakening storage.
3. Extraction attacks: a ZIP/TAR containing `../escape.txt`, an
   absolute-path entry, and a symlink pointing outside the destination
   (plus a symlink loop) must each be refused with the folder untouched
   and nothing written outside it; a quarantined archive's extracted
   files must carry `com.apple.quarantine` (`xattr -l` on an output).
4. Trash-only: a cleanup/duplicate/sync Trash action followed by
   `undoLastBatch` restores the WHOLE batch (a previous bug restored
   only one file); no user-file delete path exists outside TrashService.
5. No network: run with a proxy/packet capture (or Little Snitch-style
   monitor) and confirm zero connections on launch, indexing, update
   check, and activation.
6. Sandbox: confirm the default Downloads/Documents/Desktop flow —
   what prompts, what is visible before/after grants — and that no
   granted folder leaks into indexing via a symlink.

### Signing + notarization (Developer ID, outside the App Store)

These steps are for the developer on their Mac; nothing here is automated
and no certificate or credential is stored in this repo.

1. In Xcode, set **Signing Certificate: Developer ID Application** and
   confirm **Hardened Runtime** is on (the project sets
   `ENABLE_HARDENED_RUNTIME = YES`).
2. Archive: **Product → Archive**, then **Distribute App → Developer ID
   → Upload** (or export and notarize manually):
   ```sh
   # After exporting FileRadar.app:
   ditto -c -k --keepParent FileRadar.app FileRadar.zip
   xcrun notarytool submit FileRadar.zip --keychain-profile "AC_NOTARY" --wait
   xcrun stapler staple FileRadar.app
   spctl -a -vvv -t install FileRadar.app   # Gatekeeper check
   ```
   `AC_NOTARY` is a notarytool keychain profile the developer creates
   with their own App Store Connect API key — it is not in this repo and
   must never be committed.
3. For a Sparkle update feed (future — coordinator decision, not a
   one-line edit): host an appcast XML over HTTPS, sign updates with an
   EdDSA key (`generate_keys` from Sparkle), add the Sparkle framework +
   `SUFeedURL` + a network-client entitlement to the project, and only
   then reintroduce a feed fetch in `UpdateService` (there is currently
   no feed-URL property at all, deliberately). Until then, updates are
   off and the in-app check honestly says so.

## UNTESTED — what could not be verified

This code was **not compiled on this Linux VM (no Xcode/macOS here)**.
Nothing below is a guess about a failure — it is a list of things that
must be checked on a Mac before any claim of "working" is made:

- **Compilation.** No Swift compiler was available here. Syntax was
  checked only by brace/paren balance and manual review (see Verification
  below). Expect compiler errors on first Xcode build, especially:
  `NavigationSplitView` + `.inspector` + toolbar placement,
  `.onKeyPress(.space)` behaviour inside a `List`, `AppShortcutsProvider`
  phrase syntax, `QLPreviewPanel` data-source bridging, and the
  `FileCollectionView` `List(selection:)` binding type.
- **Vision behaviour.** OCR accuracy, language correction, and
  feature-print distance thresholds (`lookAlikeThreshold = 0.25`) are
  uncalibrated — the threshold is a starting guess, not a measured value.
  The `ResumeOnce` guard in `OCRService` is defensive code, not a tested
  fix for a double-resume.
- **Quick Look.** `QLPreviewPanel` wiring, Space-key handling, and
  multi-file preview navigation are untested.
- **Menu bar drag-out.** Dragging an `NSURL` item provider out of a
  `MenuBarExtra` window onto Finder/Desktop is untested; macOS may
  restrict drags from menu-bar windows.
- **Sparkle feed.** No feed exists, no Sparkle framework is bundled, and
  `UpdateService` performs no install. Any "auto-update" claim would be
  false until the feed + framework step above is done.
- **Global hotkey.** `NSEvent.addGlobalMonitorForEvents` requires Input
  Monitoring permission and does not deliver key events to a sandboxed
  app in all configurations; the in-app CommandMenu shortcut is the
  reliable path. Configurable-shortcut editing UI is not built (Settings
  documents the default only).
- **Saved searches.** Not implemented (listed in the checklist as missing).
  The search parser, chips, and results are implemented; persisting a
  named search and listing it in the sidebar is still to build.
- **Manual tag editing.** Auto-tags are implemented; a UI to add/remove/
  recolour manual tags is not built.
- **Parcel export UI.** `ParcelExportService` is implemented but no button
  in the UI calls it yet. Wire it to a selection action before release.
- **Corrupt-file detection.** Health checks cover zero-byte and legacy
  formats; a genuinely corrupt (truncated/unreadable) file is not
  currently flagged. Do not advertise "corrupt detection" until a read-
  validation pass is built and tested.
- **AppIntents in Shortcuts.** Intents compile-target only in theory;
  whether they appear and run in Shortcuts, and the out-of-process
  licence-gating limitation noted above, are untested.
- **Sandbox behaviour.** Whether the chosen entitlements suffice for the
  default Downloads/Documents/Desktop indexing flow (vs. prompting the
  user to pick each folder) is untested and is the first thing to check
  on a real Mac.
- **Security hardening (2026-10-27).** The Keychain migration, the
  Debug/Release entitlements split + build guard, staged/confined
  archive extraction, quarantine propagation, and the Trash batch-undo
  fix are all static-only changes: none has run on a Mac. Work through
  the six checks in "What a Mac build pass must still verify
  (security)" before any release claim.
- **Performance.** Indexing speed, thumbnail loading for large libraries
  (thumbnails currently load synchronously via `NSImage(contentsOf:)` in
  `FileCardView` — this will stutter on big libraries and should be
  moved to an async thumbnail cache before release), and Vision batch
  throughput are all unmeasured.
- **The hand-written `.xcodeproj`.** It was generated by script, not by
  Xcode. Treat it as a starting point; the fallback in step 2 of Build
  steps (fresh Xcode project + add sources) is the reliable path if it
  fails to open.
- **App Icon / asset catalog.** None is shipped.
- **Iteration 1 (Finder replacements, 2026-10-26).** As with the rest
  of this codebase, none of this was compiled or run on a Mac. In
  particular, check on first build: the `NavigationSplitView` + tab
  strip + dual-pane layout composition; `.onDrop` provider loading in
  the sidebar tray and panes; `NSOpenPanel` folder picking from the
  queue/stack/compare flows; `Process` calls to `/usr/bin/unzip`,
  `/usr/bin/tar`, `/usr/bin/ditto`, `/usr/bin/git` (and behaviour when
  git is absent); `MainActor.run` usage in `TransferQueue`; the
  `DisclosureGroup`-in-`Form` inspector layout; and the new
  `Destination` cases in every `switch` over destinations.
  - Tabs are a SwiftUI strip inside the window, **not** macOS NSWindow
    tabbing; Jump Panes moves an active-pane highlight, not AppKit
    first-responder focus. Do not describe them as system tabs/focus
    until a Mac pass wires and tests that.
  - Transfer progress is per file, not per byte; pause/cancel act
    between files, not mid-file.
  - Archive browsing lists entries only; opening a single file from
    inside an archive without extracting the whole archive is not
    built — extract first, then open.
  - Permissions in the inspector are read-only display; editing is
    not built.
  - Git badges depend on a local `git` binary and a `.git` directory
    found by walking up at most 6 levels; a missing binary yields no
    badge, never an error surface — all untested.
  - Remote locations (WebDAV/SFTP) are **not built** (see the checklist
    row): no network entitlement was added, and no SFTP library is
    bundled. Adding them later requires revisiting the privacy posture
    first.
  - Pricing is unchanged: $8 launch, then $19 one-time. Nothing in
    `licensing/` was touched by iteration 1.
  - **Muse chat (2026-10-27).** Never compiled; no live Model API call;
    no sign-in/refresh flow exercised; no voice hardware test; no
    Keychain round-trip on device. Verify on a Mac: Xcode build
    (especially `ContentView`'s custom init alongside its `@State` /
    `@EnvironmentObject` wrappers, and the two-parameter `.onChange`
    forms); the speech-recognition entitlement key (delete it if
    Xcode/codesign rejects it); OAuth authorize/token paths against the
    real provider (currently conventional derivations from the base
    URL, flagged verify-in-dashboard); the `fileradar` URL scheme plus
    mic/speech permission strings; one connected smoke test (send →
    streaming reply → one approval-gated tool → logout/history
    separation); demo/site Muse panels in a real browser.

## Verification actually performed (on this Linux VM)

- File inventory + line counts (see below).
- Brace/paren/bracket balance check across all `.swift` files (balanced
  after fixes; see report to the build coordinator for the exact script
  result).
- Licence-checksum algorithm cross-checked against the real backend:
  serials generated by `licensing/serials.py` validate under a Python
  mirror of the Swift `validate`/`checksumChar` logic, and tampered
  serials fail. (Python mirror, not the Swift code running — the Swift
  implementation itself is uncompiled. Coordinator fix, 2026-10-26: the
  app originally used a different FNV-1a checksum scheme that would have
  rejected backend-issued serials; it was rewritten to the backend spec.)
- Grep checks: no personal names, personal emails, phone numbers, or
  credentials in the source; the only contact string is
  `support@metaphasic.net`; no fabricated testimonials, numbers, or
  badges anywhere.
- Hardening greps (2026-10-27, see the coordinator report for counts):
  `removeItem` only in licence-state + staging cleanup; no
  `URLSession` or other network API; no `get-task-allow = true` in the
  Release entitlements; no `print`/`NSLog`/`os_log`; no quarantine
  removal (`removexattr` absent; `setxattr` only adds quarantine to
  extracted files); no serial stored in UserDefaults or JSON.
- No file was published, no money was spent, no payment was processed.

## File inventory

See the build coordinator's report for the full list with line counts.
In brief: 23 Swift source files (21 original + `Services/
IterationServices.swift` + `Views/IterationViews.swift`) + `Info.plist` +
entitlements + `FileRadar.xcodeproj/project.pbxproj` + this README +
`DESIGN.md`. Both new files are registered in the Xcode project's
Compile Sources phase; the fallback in step 2 of Build steps (fresh
Xcode project + add sources) still applies if the hand-written project
fails to open.

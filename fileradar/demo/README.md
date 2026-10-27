# FileRadar — Web Demo

A working, self-contained static demo of the FileRadar file-manager concept.
It is **not the real Mac app** and it does not touch your real files.

## How to open it

Just open `index.html` in any modern browser (double-click it, or drag it
into a browser window). No build step, no server, no install.

- No internet connection is needed: all CSS and JavaScript are local files
  (`demo.css`, `demo.js`, `sample-data.js`). There are no external
  dependencies, fonts, or trackers.
- Nothing leaves your browser: there are no uploads, no accounts, and no
  network requests. Dragging, trashing, and restoring all happen in memory
  on the sample library only, and are lost when the page is reloaded.

## What works

- **Home dashboard** — recent files plus one shelf per kind (Images, Videos,
  Music, Documents, Archives, Apps), with abstract thumbnails generated in
  code (CSS/SVG). No images were copied from any other product or site.
- **Library sidebar** — Recents, All Files, each kind, Smart Folders
  (Large Files over 100 MB, Screenshots), and pinned folders (Downloads,
  Desktop, Documents, Projects).
- **Search** — type plain-language queries and they are parsed into visible
  filter chips that read like sentences, e.g. `images from last week over
  100 MB`, `screenshots`, `receipts`, `videos over 500 MB`, `drafts`.
  Chips animate in from the search box and can be removed one at a time.
  Search matches file names, tags, and embedded (OCR/document) text.
  Relative dates ("last week", "last month") are anchored to the newest
  sample date (25 Oct 2026) so the demo behaves the same whenever opened.
- **Preview / inspector** — click any file (or focus it and press Space,
  like Quick Look) for dimensions, duration, camera, download source,
  location, and tags, with a plain-language explanation of each auto-tag.
- **Grid / list views, sorting** (name, date, size, kind), and a **card-size
  slider** (S / M / L).
- **Direct manipulation** — drag files onto a pinned folder to "move" them
  there (demo-local, with Undo), drag files to the Trash drop zone, and
  multi-select with Cmd/Ctrl + click. Selection state is shown in the
  toolbar.
- **Timeline view** — the same files grouped by month, for browsing by when
  things happened.
- **Disk Map** — a simple treemap where block size reflects file size;
  click a block for its details.
- **Smart Collections** — Receipts & Invoices, Unfinished Drafts, and
  Screenshots with Text.
- **Two looks, each in light and dark** — use the "Colourful look" /
  "Minimal look" toggle (warm, colourful vs. black-white-grey) and the
  Light / Dark toggle. One layout and type scale under both looks.
- **Demo Trash with Undo** — destructive demo actions go to a demo Trash
  and can be undone; nothing is ever really deleted.
- **Dual pane (off by default)** — the "Dual pane" button in the top bar
  shows two sample folders side by side. Drag files between panes, or
  drag the Drop Stack onto a pane. Jump panes with Alt + 1 (left) and
  Alt + 2 (right), or with the "Focus this pane" buttons. Turning dual
  pane off returns to the previous view; the default stays shelves and
  search.
- **Tabs** — a tab bar under the top bar holds one tab per open sample
  folder, plus Home. Clicking a pinned folder opens its tab; tabs can be
  closed and reopened within the session ("Reopen closed tab"). Tabs
  live in memory only and are lost on reload, like everything else here.
- **Drop Stack** — a tray in the sidebar. Drag sample files onto it to
  hold them, then drag the tray itself onto a pinned folder, a tab, or a
  dual pane to move the whole stack at once (with Undo). Clearing the
  stack never touches the files.
- **On-demand folder sizes** — the sidebar "Folder sizes" section lists
  every sample folder with a Calculate button (or "Calculate all"). Sizes
  are summed after a short delay so the page never blocks while counting,
  and appear in dual-pane headers once known. Sorting now also offers
  Date added and Date modified; the sample library records a single date
  per file, so both keys sort on that date in the demo.
- **Modular inspector** — Preview, Info, Tags, and Permissions as
  collapsible modules in one inspector panel, reusing the previous
  inspector content. Permissions in the demo are illustrative only: the
  sample library carries no real macOS permissions, and the panel says so.
- **Command palette** — Cmd/Ctrl + K (or the "⌘K Commands" button) lists
  every demo action: views, folders, panes, tabs, sorts, looks, and the
  locked pages. Type to filter, use arrow keys + Enter to run, Esc to
  close.
- **Keyboard & accessibility** — Cmd/Ctrl + F focuses search, arrow keys
  move between file cards, Space/Enter opens the inspector, Esc closes it.
  Cards, buttons, and filters carry aria labels, and focus states are
  visible. Contrast follows the look/theme in use.

## Muse

- **Sidebar entry "Muse — not connected"** opens a Muse panel in its
  not-connected state. It explains that chat in the full app is powered
  by Muse Spark through Meta's Model API and requires a Meta developer
  configuration, and that this demo cannot connect.
- **The Connect button does not fake a connection.** Clicking it only
  shows a plain notice that connecting requires a Meta developer
  configuration (see the FileRadar README) and that the demo cannot
  connect. The panel stays not connected; no session is started and no
  state changes to "connected".
- **Guided tour, examples only.** The panel also shows two static,
  clearly labeled example tool cards — an Approve/Deny card for
  "Move to Trash" and a read-only preview card. They are example copy
  only: there are no live Muse messages, no simulated replies, no fake
  transcripts, and no fake tool results, and neither card does anything.
- **No live connection exists in this demo.** Your personal Muse app
  history and memory do not carry over into FileRadar, and FileRadar is
  not affiliated with or endorsed by Meta. The demo banner stays
  accurate: everything here is a sample library and nothing leaves your
  browser.

## What is demo-only / locked

- **Duplicates, Clean Up, folder sync/compare, archive browsing, and
  workspaces are DEMO-LOCKED.** Their pages explain honestly that they
  unlock with a paid licence in the full Mac app. There is **no
  purchase flow and no payment form** in this demo, and the lock screens
  make no claim about price or checkout.
- **The sample library is invented** — 48 files with invented names, sizes,
  dates, tags, sources, dimensions, and durations. It is not a real disk,
  and totals (e.g. in the Disk Map) cover only those 48 files.
- **The sales-site link is a relative placeholder** (`../site/index.html`).
  No domain is claimed for it, and the target page is built separately;
  the link may not resolve until that page exists.
- **No testimonials, sales numbers, or trust badges** appear anywhere in
  this demo, deliberately.
- **Contact shown is only support@metaphasic.net.** No personal names,
  personal emails, phone numbers, or addresses appear in the demo.

## Design principles implemented

These come from the verified research in
`../files/design-awards-research.md` (20 Apple-honored Mac apps — Apple
Design Awards + App Store Awards Mac App of the Year). No additional award
winners or claims are invented here:

1. Native macOS-style controls and keyboard navigation.
2. One job per view (Home, Search, Cleanup, Timeline, Disk Map).
3. Content as interface: big thumbnails, large previews, hover inspector.
4. Direct manipulation: drag between shelves/folders, drag to Trash,
   multi-select.
5. Motion that explains: chips animate in; trash/move actions offer Undo
   and name their destination.
6. Plain-language intelligence: sentence-like chips, tags explained in
   words, no AI branding noise.
7. Two looks from one system (colourful / minimal, each light + dark).
8. Micro-delight: kind empty states, satisfying Trash/undo, Timeline as
   discovery.
9. Accessibility as design: keyboard-only path, focus states, aria labels.
10. Trust through restraint: the demo banner, demo Trash with undo,
    no uploads.

## UNTESTED — honest status

- **No browser testing was performed.** This subagent has no live-browser
  tool: the demo was written and statically checked only (see below). It
  has not been opened in Chrome, Safari, or Firefox, on Mac or elsewhere.
  Visual layout, drag-and-drop, keyboard navigation, and the look/theme
  toggles therefore need a real browser pass before this is shown to users.
- **Static checks actually run:** JavaScript syntax check (`node --check`
  on both JS files), sample-data count and kind distribution (48 files,
  unchanged), and a grep for external URLs and personal contact details
  (only support@metaphasic.net appears; the only `http://` string in the
  code is the SVG `xmlns` namespace identifier, which browsers do not
  fetch; no phone-number patterns). New in this iteration: the same
  checks were re-run after the dual-pane, tabs, Drop Stack, folder-size,
  inspector, palette, and locked-page changes.
- **Known limitations to verify in that browser pass:** duplicate SVG
  gradient IDs when the same file appears on two shelves (harmless in most
  browsers, but worth confirming the thumbnails still render); the
  `../site/index.html` placeholder link (see above); and small-screen
  layout below 700 px, where the sidebar stacks above the file grid.
  The iteration-1 additions (dual-pane drag between panes, tab drops,
  Drop Stack tray dragging, palette keyboard navigation, folder-size
  timing) are likewise written and statically checked only — they need
  the same browser pass.

## Security posture (hardening pass, 27 Oct 2026)

- **XSS / escaping:** every value interpolated into `innerHTML` in
  `demo.js` passes through `esc()`, which escapes `& < > " '`. That
  covers the search-input path (user words become filter chips, rendered
  only via `esc()`), file names, tags, locations, sources, dimensions,
  camera, duration, kinds, ids, folder names, tab labels, and toast
  messages. The only unescaped HTML in rendered output is static
  literals written in `demo.js` itself (e.g. the Search intro's `<em>`
  markup and the locked-page copy, which is escaped at render time);
  no search input or sample-data field is ever inserted raw.
- **No external resources:** local CSS/JS only. The sole `http://`
  string in the code is the SVG `xmlns` namespace identifier, which
  browsers do not fetch. No scripts, fonts, trackers, or analytics.
  The only cross-page link is the relative `../site/index.html`.
- **localStorage inventory:** the demo writes nothing to localStorage
  (or sessionStorage, or cookies). All state — selection, Trash, moves,
  tabs, Drop Stack, folder sizes — lives in memory and is lost on
  reload. The sales site separately stores only two theme preferences
  (see `../site/README.md`).
- **No inline event handlers, no `javascript:` URLs** in `index.html`.
- **Locked features stay locked:** sync/compare, archive browsing,
  workspaces, duplicates, and Clean Up render disabled lock screens
  with no purchase form; Permissions remain marked illustrative.
- **Not verified in a browser:** this pass was static only (see
  UNTESTED above). Escaping changes render the same text for the
  current 48-file library (none of its values contain markup
  characters), but a real browser pass is still owed before users see it.

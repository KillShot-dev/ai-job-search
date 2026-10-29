# FileRadar — Competitive analysis (top 5 paid Finder replacements)

**Date:** 2026-10-27 · **Sources:** existing `finder-replacements-research.md`, DockDuck / Pizazoo / vendor-reported 2026 comparisons. Prices are as reported, not purchase-verified.

## Top 5

| # | App | Pricing angle | Layout | Signature strengths | Weaknesses FileRadar can exploit |
|---|-----|---------------|--------|---------------------|----------------------------------|
| 1 | **ForkLift 4** | ~$19.95 (1 yr updates) / $34.95 (2 yr); family tiers | Dual-pane + tabs | Transfer queue (pause/resume), remote servers, folder sync/compare, batch rename, polished orthodox UI | Remote/cloud-first; denser chrome; no on-device “intelligence” story (NL search, shelves, OCR tags) |
| 2 | **Path Finder** | $29.95/yr or term keys (~$33–$123) | Dual browser + modules | Drop Stack, modular inspector, ACLs, batch rename, Smart Folders, 20-year depth | Subscription push; kitchen-sink density; looks like “Finder++” not a calm product |
| 3 | **Commander One PRO** | Free + PRO ~$29.99 lifetime | Dual-pane, F-keys | Keyboard-first / F-keys, archives-as-folders, remotes/cloud/MTP, unlimited tabs, ops queue | Classic Norton chrome; PRO gate on remotes; weaker modern preview aesthetics |
| 4 | **QSpace Pro** | ~$13–$30 one-time (+ extensions) | Multi-pane grid | Cheap multi-pane, workspaces, custom layouts | Extensions nickel-and-dime servers/rename; less “product identity” |
| 5 | **Bloom** | ~$16 one-time (≤3 Macs) | Up to quad pane | Most Finder-like polish, regex rename, undo history, minimal native look | Shallow vs Path Finder/ForkLift power set; smaller brand footprint |

Honorable (not ranked as paid leaders): Marta (free beta, stalled), Nimble Commander (free OSS), DockDuck/Captain’s Deck (newer paid entrants).

## Feature matrix vs FileRadar

| Capability | ForkLift | Path Finder | Commander One | QSpace | Bloom | FileRadar (pre-upgrade) | FileRadar target |
|---|---|---|---|---|---|---|---|
| Dual-pane (optional) | ● | ● | ● | ● multi | ● multi | ● optional | ● + folder pick / copy-vs-move |
| Tabs + restore | ● | ● | ● | ● | ● | ● in-window | ● polish |
| Transfer queue UX | ★ | ○ | ● | ○ | ○ | ● sidebar only | ★ HUD + per-item cancel |
| Drop Stack / holding | ○ | ★ | ○ | ○ | ○ | ● | ● |
| Batch rename | ● | ● | ○/? | ● ext | ★ regex | ● Extras preview | ★ selection sheet + shortcut |
| Quick Look / preview | ○ system | ● modules | ○ | ○ | ● | ● Space (1 file) | ★ multi-select QL + preview strip |
| Favorites / sidebar | ● | ● | ● | ● | ● | ● | ● |
| Search depth | ○ | ● | ● | ○ | ○ | ★ NL chips + index | ★ |
| Workspaces | ○ | ○ | ○ | ★ | ★ | ● paid | ● |
| Archives as folders | ○ | ○ | ★ | ○ | ○ | ● paid | ● |
| Folder sync/compare | ★ | ● | ○ | ● | ○ | ● paid preview | ● |
| Remotes (SFTP/cloud) | ★ | ● | ★ | ● ext | ○ | deliberately omitted | omit (privacy) |
| On-device OCR / tags / cleanup | ○ | ○ | ○ | ○ | ○ | ★ | ★ differentiator |
| Pricing story | update window | subscription | freemium | cheap + addons | cheap one-time | $8→$19 one-time + trial/SK | stay one-time |

● present · ★ standout · ○ weak/absent

## UX polish lessons (apply, don’t copy)

1. **ForkLift:** transfers must feel *visible and safe* — progress, pause, cancel, never buried only in a sidebar strip.
2. **Path Finder:** Drop Stack + modular inspector — depth via disclosure, not toolbar sprawl.
3. **Commander One:** keyboard discoverability (shortcuts next to actions; Cmd-K already).
4. **QSpace / Bloom:** workspaces + restrained chrome; beauty by removal (matches DESIGN.md / awards research).
5. **All five:** dual-pane is expected by power users but should stay optional — FileRadar’s default remains shelves + search.

## Gaps this upgrade closes (priority)

1. Transfer **HUD** when jobs are active (ForkLift parity on feel).
2. Dual-pane **right-folder picker** + Option-drop **copy** vs move.
3. **Batch rename sheet** on selection (Cmd-Shift-R), not only Extras sample-of-20.
4. Space → Quick Look for **all selected**; optional **preview strip** under the detail.
5. Stronger drop-target wash + Add-to-Drop-Stack / rename in context menus; keyboard trash / select-all paths.

## Deliberately not chasing

Remote servers (needs network entitlement; breaks on-device promise), ACL editors, hex viewers, subscription pricing, multi-pane-beyond-two as default, copying any competitor’s icons/copy/layout.

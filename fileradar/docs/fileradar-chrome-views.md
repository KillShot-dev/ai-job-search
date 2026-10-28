# FileRadar chrome views

Shared layout IDs for Mac and Windows. Default: **`radarGlass`**.

Persisted preference key: `chromeView` (UserDefaults / `@AppStorage`).

## Shared IDs

| ID | Name | Letter | Accent |
| --- | --- | --- | --- |
| `radarGlass` | Radar Glass | A | Electric blue |
| `previewTheater` | Preview Theater | B | Calm blue (light-capable) |
| `commandRail` | Command Rail | C | Teal |
| `workspaceTabs` | Workspace Tabs | D | Amber |

Toggle: toolbar chrome glyph + **View → Chrome**. Cycle: ⌥⌘C.

## Mac

| View | Composition |
| --- | --- |
| **Radar Glass** | Frosted sidebar with radar watermark, pill path crumbs, dual-pane, **docked** bottom transfer drawer |
| **Preview Theater** | Slim places rail, dual-pane, **top** transfer strip, large right Quick Look theater |
| **Command Rail** | Vertical icon rail, sync pill between panes, floating transfer pill, keyboard legend footer |
| **Workspace Tabs** | Work / Photos / Archive tabs, Drop Stack + disk bar, dual-pane, right **Queue** drawer |

Dual-pane browsing remains the core in all four. Shelves stays a secondary destination.

### Screenshots

- `media/fileradar-mac-chrome-a.png` — Radar Glass  
- `media/fileradar-mac-chrome-b.png` — Preview Theater  
- `media/fileradar-mac-chrome-c.png` — Command Rail  
- `media/fileradar-mac-chrome-d.png` — Workspace Tabs  

### Icons

See `docs/fileradar-icon-system.md`. Rich multi-layer glyphs apply in every chrome.

### Dev snapshot

```bash
open -n ~/Desktop/FileRadar/dist/FileRadar.app \
  --env FILERADAR_FORCE_UNLOCK=1 \
  --env FILERADAR_CHROME_VIEW=radarGlass \
  --env FILERADAR_SNAPSHOT_TRANSFER=1 \
  --env FILERADAR_SNAPSHOT_PATH=/path/to/out.png
```

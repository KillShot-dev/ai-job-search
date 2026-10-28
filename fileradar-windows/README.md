# FileRadar for Windows

WinUI 3 / .NET 8 Explorer replacement. **Default Home is Showcase** — unified Mac/Windows look (`docs/fileradar-unified-look.md`): sidebar | Shelves + Recents | Inspector.

## Unified look (v1)

- Tokens: `FileRadarChrome` — accent `#007AFF`, radii 12/8, space 20/28/16, selection stroke + wash
- Materials: Mica `BaseAlt`; frosted Transfer HUD capsule when jobs run
- Drop Stack tray + disk bar in sidebar; dual-pane optional (off by default)
- Inspector: preview-first Info / Tags / More modules; Show in Explorer
- Quiet toolbar ≤6 + overflow (rename, compare/sync, workspace, shortcuts)

## Run (portable exe)

```
c:\Users\saran\Desktop\FileRadar Windows\dist\FileRadar.exe
```

Keep the whole `dist\` folder together (WinAppSDK self-contained).

## Build / publish

```powershell
cd fileradar-windows\FileRadar
dotnet publish -c Release -r win-x64 -p:Platform=x64 --self-contained true -p:PublishSingleFile=false -o ..\..\dist
```

Optional UI capture: `$env:FILERADAR_CAPTURE=1` → `fileradar-windows-unified-home.png` beside the exe.

## Version

`1.0.0-b1`

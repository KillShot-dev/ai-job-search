# FileRadar for Windows

WinUI 3 / .NET 8 Explorer replacement. **Default chrome: Radar Glass** dual-pane (`radarGlass`). Four chrome views + rich icon system.

## Chrome views

IDs match Mac: `radarGlass` · `previewTheater` · `commandRail` · `workspaceTabs`.  
Toolbar **Chrome** button / `Ctrl+Shift+C` / overflow **View → Chrome**. Persisted in `%LocalAppData%\FileRadar\settings.json`.

## Look

- Tokens: `FileRadarChrome` — accent follows chrome (blue / teal / amber)
- Materials: Mica `BaseAlt`; docked / top-strip / Queue transfer surfaces
- Rich PNG icons (`Assets/Icons`, `IconCatalog`) — not thin WinUI glyphs
- Drop Stack + disk bar; dual-pane default; inspector for Preview Theater

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

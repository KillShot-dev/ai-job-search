# FileRadar for Windows

WinUI 3 / .NET 8 Explorer replacement. **Default Home is Showcase** — three-pane Apple-like layout matching the Mac mockup (Shelves + Recents + Inspector).

## Features (v1)

- **Showcase Home (default):** horizontal Shelves album cards, Recents thumbnails with relative time, rich Inspector (preview, metadata, tags, Show in Explorer)
- Soft frosted Mica chrome, calm slate + blue accent; Dark appearance by default
- Sidebar: Library destinations + Favorites + disk-free bar
- Quiet toolbar (search + compact appearance / view / inspector) — no Look: Modern footer, no Colourful/Minimal chrome, no Up/Trash/Open strip on Home
- Search, Cleanup, Duplicates, Timeline, Recycle Bin, browse

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

Optional UI capture: set `FILERADAR_CAPTURE=1` before launch to write `fileradar-windows-apple-home.png` beside the exe.

## Version

`1.0.0-b1`

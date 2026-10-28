# FileRadar for Windows

WinUI 3 / .NET 8 Explorer replacement matching the Mac FileRadar look system.

## Features (v1)

- Apple-like **Modern** default (neutral slate + blue accent, Mica frosted chrome)
- Appearance: System / Light / Dark in primary toolbar
- Calm Look cycle (Modern ↔ Elegant) in nav footer — Colourful/Minimal de-emphasized
- NavigationView sidebar: Library + Places
- Home shelves, grid/list, inspector, dual-pane, staging trash, search

## Run (portable exe)

Double-click:

```
c:\Users\saran\Desktop\FileRadar Windows\dist\FileRadar.exe
```

Or unzip `FileRadarWindows-1.0.0-b1-20261028.zip` and run `FileRadar\FileRadar.exe`.

**WinAppSDK / runtime deps must sit beside the exe.** This is an unpackaged self-contained publish (`WindowsPackageType=None`, `WindowsAppSDKSelfContained=true`). Keep the whole `dist\` folder together — do not copy `FileRadar.exe` alone.

True single-file (`PublishSingleFile=true`) **publishes but crashes at launch** on WinUI 3 / Windows App SDK (CLR unhandled exception). Use the portable folder layout instead.

## Build / publish

```powershell
cd fileradar-windows\FileRadar
dotnet restore
dotnet build -c Release -r win-x64 -p:Platform=x64
dotnet publish -c Release -r win-x64 -p:Platform=x64 --self-contained true -p:PublishSingleFile=false -o ..\..\dist
```

## Version

`1.0.0-b1`
